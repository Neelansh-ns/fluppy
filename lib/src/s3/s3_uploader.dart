import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/fluppy_file.dart';
import '../core/events.dart';
import '../core/uploader.dart';
import 's3_options.dart';
import 's3_types.dart';

/// S3 Uploader implementation supporting both single-part and multipart uploads.
///
/// Provides the same functionality as [@uppy/aws-s3](https://uppy.io/docs/aws-s3/):
/// - Single-part uploads via presigned URLs
/// - Multipart uploads for large files
/// - Pause/resume capability
/// - Progress tracking
/// - Automatic retry with exponential backoff
///
/// Example:
/// ```dart
/// final uploader = S3Uploader(
///   options: S3UploaderOptions(
///     getUploadParameters: (file, options) async {
///       final response = await backend.getPresignedUrl(file.name);
///       return UploadParameters(
///         method: 'PUT',
///         url: response.url,
///         headers: {'Content-Type': file.type ?? 'application/octet-stream'},
///       );
///     },
///     // ... other callbacks
///   ),
/// );
/// ```
class S3Uploader extends Uploader with RetryMixin {
  /// Configuration options.
  final S3UploaderOptions options;

  /// HTTP client for making requests.
  final http.Client _httpClient;

  /// Cached temporary credentials.
  TemporaryCredentials? _cachedCredentials;

  /// Files that are paused.
  final Set<String> _pausedFiles = {};

  /// Creates an S3 uploader with the given options.
  S3Uploader({
    required this.options,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Retry configuration derived from options
  RetryConfig get _retryConfig => RetryConfig(
        maxRetries: options.retryOptions.maxRetries,
        initialDelay: options.retryOptions.initialDelay,
        maxDelay: options.retryOptions.maxDelay,
      );

  @override
  bool get supportsPause => true;

  @override
  bool get supportsResume => true;

  @override
  Future<UploadResponse> upload(
    FluppyFile file, {
    required ProgressCallback onProgress,
    required EventEmitter emitEvent,
    CancellationToken? cancellationToken,
  }) async {
    // Decide whether to use multipart
    if (options.useMultipart(file)) {
      return _uploadMultipart(
        file,
        onProgress: onProgress,
        emitEvent: emitEvent,
        cancellationToken: cancellationToken,
      );
    } else {
      return _uploadSinglePart(
        file,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    }
  }

  @override
  Future<bool> pause(FluppyFile file) async {
    _pausedFiles.add(file.id);
    return true;
  }

  @override
  Future<UploadResponse> resume(
    FluppyFile file, {
    required ProgressCallback onProgress,
    required EventEmitter emitEvent,
    CancellationToken? cancellationToken,
  }) async {
    _pausedFiles.remove(file.id);

    if (file.isMultipart && file.uploadId != null) {
      // Resume multipart upload
      return _resumeMultipart(
        file,
        onProgress: onProgress,
        emitEvent: emitEvent,
        cancellationToken: cancellationToken,
      );
    } else {
      // Restart single-part upload
      return upload(
        file,
        onProgress: onProgress,
        emitEvent: emitEvent,
        cancellationToken: cancellationToken,
      );
    }
  }

  @override
  Future<void> cancel(FluppyFile file) async {
    _pausedFiles.remove(file.id);

    // Abort multipart upload if in progress
    if (file.isMultipart && file.uploadId != null && file.key != null) {
      try {
        await options.abortMultipartUpload(
          file,
          AbortMultipartOptions(
            uploadId: file.uploadId!,
            key: file.key!,
          ),
        );
      } catch (_) {
        // Ignore errors during abort
      }
    }
  }

  @override
  Future<void> dispose() async {
    _httpClient.close();
  }

  // ============================================
  // Single-Part Upload
  // ============================================

  /// Uploads a file using a single presigned URL request.
  Future<UploadResponse> _uploadSinglePart(
    FluppyFile file, {
    required ProgressCallback onProgress,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();

    // Get upload parameters
    final params = await options.getUploadParameters(
      file,
      UploadOptions(signal: cancellationToken),
    );

    cancellationToken?.throwIfCancelled();

    // Get file data
    final bytes = await file.getBytes();

    cancellationToken?.throwIfCancelled();

    // Create request
    final request = http.Request(params.method, Uri.parse(params.url));

    // Add headers
    if (params.headers != null) {
      request.headers.addAll(params.headers!);
    }

    // Add body
    request.bodyBytes = bytes;

    // Upload to S3 with retry (THIS is what Fluppy should retry - the actual HTTP upload)
    final response = await withRetry(
      () => _sendWithProgress(
        request,
        file.size,
        onProgress,
        cancellationToken,
        expires: params.expires,
      ),
      config: _retryConfig,
      cancellationToken: cancellationToken,
    );

    // Check response
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Check if this is an expired presigned URL
      if (S3ExpiredUrlException.isExpiredResponse(response.statusCode, response.body)) {
        throw S3ExpiredUrlException(
          statusCode: response.statusCode,
          body: response.body,
        );
      }
      throw S3UploadException(
        'Upload failed with status ${response.statusCode}',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    // Extract ETag and location
    final eTag = response.headers['etag'];
    final location = response.headers['location'] ?? params.url.split('?').first;

    return UploadResponse(
      location: location,
      eTag: eTag,
    );
  }

  // ============================================
  // Multipart Upload
  // ============================================

  /// Uploads a file using multipart upload.
  Future<UploadResponse> _uploadMultipart(
    FluppyFile file, {
    required ProgressCallback onProgress,
    required EventEmitter emitEvent,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();

    // Initialize multipart upload
    final createResult = await options.createMultipartUpload(file);
    file.uploadId = createResult.uploadId;
    file.key = createResult.key;
    file.isMultipart = true;

    cancellationToken?.throwIfCancelled();

    // Upload parts
    return _uploadParts(
      file,
      onProgress: onProgress,
      emitEvent: emitEvent,
      cancellationToken: cancellationToken,
    );
  }

  /// Resumes a multipart upload.
  Future<UploadResponse> _resumeMultipart(
    FluppyFile file, {
    required ProgressCallback onProgress,
    required EventEmitter emitEvent,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();

    // List already uploaded parts
    final existingParts = await options.listParts(
      file,
      ListPartsOptions(
        uploadId: file.uploadId!,
        key: file.key!,
        signal: cancellationToken,
      ),
    );

    // Update file's uploaded parts
    file.uploadedParts.clear();
    file.uploadedParts.addAll(existingParts);

    cancellationToken?.throwIfCancelled();

    // Continue uploading remaining parts
    return _uploadParts(
      file,
      onProgress: onProgress,
      emitEvent: emitEvent,
      cancellationToken: cancellationToken,
    );
  }

  /// Uploads parts for a multipart upload.
  Future<UploadResponse> _uploadParts(
    FluppyFile file, {
    required ProgressCallback onProgress,
    required EventEmitter emitEvent,
    CancellationToken? cancellationToken,
  }) async {
    final chunkSize = options.chunkSize(file);
    final totalParts = (file.size / chunkSize).ceil();

    // Calculate already uploaded bytes
    var uploadedBytes = file.uploadedParts.fold<int>(
      0,
      (sum, part) => sum + part.size,
    );

    // Track which parts are already uploaded
    final uploadedPartNumbers = file.uploadedParts.map((p) => p.partNumber).toSet();

    // Prepare parts to upload
    final partsToUpload = <int>[];
    for (var i = 1; i <= totalParts; i++) {
      if (!uploadedPartNumbers.contains(i)) {
        partsToUpload.add(i);
      }
    }

    // Report initial progress
    onProgress(UploadProgressInfo(
      bytesUploaded: uploadedBytes,
      bytesTotal: file.size,
      partsUploaded: file.uploadedParts.length,
      partsTotal: totalParts,
    ));

    // Upload parts with concurrency limit
    final semaphore = _Semaphore(options.maxConcurrentParts);
    final futures = <Future<void>>[];

    for (final partNumber in partsToUpload) {
      // Check for pause/cancel
      if (_pausedFiles.contains(file.id)) {
        throw PausedException();
      }
      cancellationToken?.throwIfCancelled();

      final future = semaphore.run(() async {
        if (_pausedFiles.contains(file.id)) {
          throw PausedException();
        }
        cancellationToken?.throwIfCancelled();

        final part = await _uploadPart(
          file,
          partNumber: partNumber,
          chunkSize: chunkSize,
          totalParts: totalParts,
          cancellationToken: cancellationToken,
        );

        file.uploadedParts.add(part);
        uploadedBytes += part.size;

        // Report progress
        onProgress(UploadProgressInfo(
          bytesUploaded: uploadedBytes,
          bytesTotal: file.size,
          partsUploaded: file.uploadedParts.length,
          partsTotal: totalParts,
        ));

        emitEvent(PartUploaded(file, part, totalParts));
      });

      futures.add(future);
    }

    // Wait for all parts
    try {
      await Future.wait(futures);
    } on PausedException {
      file.status = FileStatus.paused;
      rethrow;
    }

    cancellationToken?.throwIfCancelled();

    // Sort parts by part number for completion
    file.uploadedParts.sort((a, b) => a.partNumber.compareTo(b.partNumber));

    // Complete the multipart upload
    final completeResult = await options.completeMultipartUpload(
      file,
      CompleteMultipartOptions(
        uploadId: file.uploadId!,
        key: file.key!,
        parts: file.uploadedParts,
        signal: cancellationToken,
      ),
    );

    return UploadResponse(
      location: completeResult.location,
      eTag: completeResult.eTag,
      key: file.key,
    );
  }

  /// Uploads a single part with retry.
  Future<S3Part> _uploadPart(
    FluppyFile file, {
    required int partNumber,
    required int chunkSize,
    required int totalParts,
    CancellationToken? cancellationToken,
  }) async {
    // Calculate byte range for this part
    final start = (partNumber - 1) * chunkSize;
    var end = start + chunkSize;
    if (end > file.size) {
      end = file.size;
    }

    // Get chunk data
    final chunkData = await file.getChunk(start, end);

    // Sign the part - USER CALLBACK (no retry, user handles it)
    final signResult = await options.signPart(
      file,
      SignPartOptions(
        uploadId: file.uploadId!,
        key: file.key!,
        partNumber: partNumber,
        body: chunkData,
        signal: cancellationToken,
      ),
    );

    cancellationToken?.throwIfCancelled();

    // Upload the part with retry
    final uploadResult = await withRetry(
      () => _doUploadPartBytes(
        url: signResult.url,
        data: chunkData,
        headers: signResult.headers,
        expires: signResult.expires,
        cancellationToken: cancellationToken,
      ),
      config: RetryConfig(
        maxRetries: options.retryOptions.maxRetries,
        initialDelay: options.retryOptions.initialDelay,
        maxDelay: options.retryOptions.maxDelay,
      ),
      cancellationToken: cancellationToken,
    );

    return S3Part(
      partNumber: partNumber,
      size: chunkData.length,
      eTag: uploadResult.eTag,
    );
  }

  /// Uploads part bytes using either custom callback or default implementation.
  Future<UploadPartBytesResult> _doUploadPartBytes({
    required String url,
    required Uint8List data,
    Map<String, String>? headers,
    int? expires,
    CancellationToken? cancellationToken,
  }) async {
    // Use custom callback if provided
    if (options.uploadPartBytes != null) {
      return options.uploadPartBytes!(
        UploadPartBytesOptions(
          url: url,
          headers: headers,
          body: data,
          size: data.length,
          expires: expires,
          signal: cancellationToken,
        ),
      );
    }

    // Use default implementation
    final response = await _uploadPartData(
      url,
      data,
      headers,
      cancellationToken,
      expires: expires,
    );

    final eTag = response.headers['etag'];
    if (eTag == null) {
      throw S3UploadException(
        'No ETag in response',
        statusCode: response.statusCode,
      );
    }

    return UploadPartBytesResult(
      eTag: eTag,
      location: response.headers['location'],
      headers: response.headers,
    );
  }

  /// Uploads part data to the presigned URL.
  ///
  /// If [expires] is provided, the request will timeout after that duration.
  Future<http.Response> _uploadPartData(
    String url,
    Uint8List data,
    Map<String, String>? headers,
    CancellationToken? cancellationToken, {
    int? expires,
  }) async {
    cancellationToken?.throwIfCancelled();

    final request = http.Request('PUT', Uri.parse(url));
    if (headers != null) {
      request.headers.addAll(headers);
    }
    request.bodyBytes = data;

    // Send request with optional timeout based on expires
    Future<http.StreamedResponse> sendFuture = _httpClient.send(request);
    if (expires != null && expires > 0) {
      sendFuture = sendFuture.timeout(
        Duration(seconds: expires),
        onTimeout: () {
          throw S3ExpiredUrlException(
            message: 'Request timed out after $expires seconds (presigned URL may have expired)',
          );
        },
      );
    }

    final streamedResponse = await sendFuture;
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Check if this is an expired presigned URL
      if (S3ExpiredUrlException.isExpiredResponse(response.statusCode, response.body)) {
        throw S3ExpiredUrlException(
          statusCode: response.statusCode,
          body: response.body,
        );
      }
      throw S3UploadException(
        'Part upload failed with status ${response.statusCode}',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    return response;
  }

  // ============================================
  // Helpers
  // ============================================

  /// Sends a request with progress tracking.
  ///
  /// If [expires] is provided, the request will timeout after that duration.
  Future<http.Response> _sendWithProgress(
    http.Request request,
    int totalBytes,
    ProgressCallback onProgress,
    CancellationToken? cancellationToken, {
    int? expires,
  }) async {
    cancellationToken?.throwIfCancelled();

    // Note: http package doesn't support upload progress tracking directly.
    // For production use, consider using dio which supports this.
    // Here we report progress before and after upload.

    onProgress(UploadProgressInfo(
      bytesUploaded: 0,
      bytesTotal: totalBytes,
    ));

    // Send request with optional timeout based on expires
    Future<http.StreamedResponse> sendFuture = _httpClient.send(request);
    if (expires != null && expires > 0) {
      sendFuture = sendFuture.timeout(
        Duration(seconds: expires),
        onTimeout: () {
          throw S3ExpiredUrlException(
            message: 'Request timed out after $expires seconds (presigned URL may have expired)',
          );
        },
      );
    }

    final streamedResponse = await sendFuture;
    final response = await http.Response.fromStream(streamedResponse);

    onProgress(UploadProgressInfo(
      bytesUploaded: totalBytes,
      bytesTotal: totalBytes,
    ));

    return response;
  }

  /// Gets temporary credentials, using cache if valid.
  ///
  /// This is exposed for users who want to implement their own upload logic
  /// using temporary credentials for reduced overhead.
  Future<TemporaryCredentials?> getTemporaryCredentials({
    CancellationToken? cancellationToken,
  }) async {
    if (options.getTemporarySecurityCredentials == null) {
      return null;
    }

    // Check if cached credentials are still valid (with 5 min buffer)
    if (_cachedCredentials != null) {
      final expirationBuffer = _cachedCredentials!.expiration.subtract(
        const Duration(minutes: 5),
      );
      if (DateTime.now().isBefore(expirationBuffer)) {
        return _cachedCredentials;
      }
    }

    // Fetch new credentials
    _cachedCredentials = await options.getTemporarySecurityCredentials!(
      CredentialsOptions(signal: cancellationToken),
    );

    return _cachedCredentials;
  }

  /// Whether temporary credentials are configured.
  bool get hasTemporaryCredentials => options.getTemporarySecurityCredentials != null;

  /// Clears cached credentials.
  void clearCredentialsCache() {
    _cachedCredentials = null;
  }

  /// Default implementation for uploading part bytes.
  ///
  /// This is exposed as a static method so users can use it as a fallback
  /// in their custom [S3UploaderOptions.uploadPartBytes] implementations.
  ///
  /// Example:
  /// ```dart
  /// uploadPartBytes: (options) async {
  ///   // Custom logic before upload
  ///   print('Uploading to ${options.url}');
  ///
  ///   // Use default implementation
  ///   return S3Uploader.defaultUploadPartBytes(options);
  /// }
  /// ```
  static Future<UploadPartBytesResult> defaultUploadPartBytes(
    UploadPartBytesOptions options,
  ) async {
    options.signal?.throwIfCancelled();

    final client = http.Client();
    try {
      final request = http.Request(options.method, Uri.parse(options.url));
      if (options.headers != null) {
        request.headers.addAll(options.headers!);
      }
      request.bodyBytes = options.body;

      // Send request with optional timeout based on expires
      Future<http.StreamedResponse> sendFuture = client.send(request);
      if (options.expires != null && options.expires! > 0) {
        sendFuture = sendFuture.timeout(
          Duration(seconds: options.expires!),
          onTimeout: () {
            throw S3ExpiredUrlException(
              message: 'Request timed out after ${options.expires} seconds',
            );
          },
        );
      }

      final streamedResponse = await sendFuture;
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (S3ExpiredUrlException.isExpiredResponse(response.statusCode, response.body)) {
          throw S3ExpiredUrlException(
            statusCode: response.statusCode,
            body: response.body,
          );
        }
        throw S3UploadException(
          'Upload failed with status ${response.statusCode}',
          statusCode: response.statusCode,
          body: response.body,
        );
      }

      final eTag = response.headers['etag'];
      if (eTag == null) {
        throw S3UploadException(
          'No ETag in response',
          statusCode: response.statusCode,
        );
      }

      options.onComplete?.call(eTag);

      return UploadPartBytesResult(
        eTag: eTag,
        location: response.headers['location'],
        headers: response.headers,
      );
    } finally {
      client.close();
    }
  }
}

/// Exception thrown when an S3 upload fails.
class S3UploadException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;

  S3UploadException(this.message, {this.statusCode, this.body});

  @override
  String toString() {
    var s = 'S3UploadException: $message';
    if (statusCode != null) {
      s += ' (status: $statusCode)';
    }
    return s;
  }
}

/// Exception thrown when a presigned URL has expired.
///
/// This is a specific type of S3 error that occurs when:
/// - The presigned URL's expiration time has passed
/// - S3 returns a 403 status with "Request has expired" message
///
/// When this exception is thrown, the caller should:
/// 1. Request a new presigned URL from the server
/// 2. Retry the upload with the new URL
class S3ExpiredUrlException extends S3UploadException {
  S3ExpiredUrlException({
    String message = 'Presigned URL has expired',
    int? statusCode,
    String? body,
  }) : super(message, statusCode: statusCode, body: body);

  /// Checks if a response indicates an expired presigned URL.
  ///
  /// AWS S3 returns 403 with a message containing "Request has expired"
  /// when the presigned URL has expired.
  static bool isExpiredResponse(int statusCode, String? body) {
    if (statusCode != 403) return false;
    if (body == null) return false;

    // AWS S3 XML response format
    return body.contains('<Message>Request has expired</Message>') ||
        body.contains('Request has expired') ||
        body.contains('ExpiredToken') ||
        body.contains('TokenExpired');
  }

  @override
  String toString() => 'S3ExpiredUrlException: $message (status: $statusCode)';
}

/// Exception thrown when an upload is paused.
class PausedException implements Exception {
  @override
  String toString() => 'Upload was paused';
}

/// A simple semaphore for limiting concurrency.
class _Semaphore {
  final int maxConcurrent;
  int _current = 0;
  final _waiters = <Completer<void>>[];

  _Semaphore(this.maxConcurrent);

  Future<T> run<T>(Future<T> Function() operation) async {
    await _acquire();
    try {
      return await operation();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_current < maxConcurrent) {
      _current++;
      return;
    }

    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }

  void _release() {
    _current--;
    if (_waiters.isNotEmpty) {
      _current++;
      _waiters.removeAt(0).complete();
    }
  }
}
