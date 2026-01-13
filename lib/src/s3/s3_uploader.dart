import 'dart:async';

import 'package:dio/dio.dart' hide ProgressCallback;

import '../core/fluppy.dart' show FluppyFile, FileStatus;
import '../core/types.dart';
import '../core/uploader.dart';
import 'fluppy_file_extension.dart';
import 'multipart_upload_controller.dart';
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
class S3Uploader extends Uploader with RetryMixin {
  /// Configuration options.
  final S3UploaderOptions options;

  /// Dio instance for making HTTP requests.
  final Dio _dio;

  /// Cached temporary credentials.
  TemporaryCredentials? _cachedCredentials;

  /// Active upload controllers for multipart uploads.
  final Map<String, MultipartUploadController> _controllers = {};

  /// Creates an S3 uploader with the given options.
  S3Uploader({
    required this.options,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  /// Retry configuration derived from options
  RetryConfig get _retryConfig => RetryConfig(
        maxRetries: options.retryConfig.maxRetries,
        initialDelay: options.retryConfig.initialDelay,
        maxDelay: options.retryConfig.maxDelay,
        retryDelays: options.retryConfig.retryDelays,
      );

  /// Determines if an error should be retried.
  bool _shouldRetryError(Object error) {
    return error is! PausedException && error is! CancelledException;
  }

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
    if (options.useMultipart(file)) {
      // Create controller for this upload
      final controller = MultipartUploadController(
        file: file,
        options: options,
        onProgress: onProgress,
        emitEvent: emitEvent,
        dio: _dio,
        retryConfig: _retryConfig,
        shouldRetry: _shouldRetryError,
      );

      _controllers[file.id] = controller;

      try {
        // Start upload - this Future completes when done, cancelled, or paused
        // If paused, controller.start() throws PausedException
        final response = await controller.start();

        // Upload completed successfully - remove controller
        _controllers.remove(file.id);

        return response;
      } on PausedException {
        // Upload was paused - keep controller alive for resume
        rethrow;
      } catch (e) {
        // Upload errored or was cancelled - remove controller

        _controllers.remove(file.id);

        rethrow;
      }
    } else {
      return await _uploadSinglePart(
        file,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    }
  }

  @override
  Future<bool> pause(FluppyFile file) async {
    // Single-part uploads don't support pause/resume
    if (!options.useMultipart(file)) {
      return false;
    }

    final controller = _controllers[file.id];
    if (controller == null) {
      return false;
    }

    controller.pause();

    return true;
  }

  @override
  Future<UploadResponse> resume(
    FluppyFile file, {
    required ProgressCallback onProgress,
    required EventEmitter emitEvent,
    CancellationToken? cancellationToken,
  }) async {
    // If file is already complete, don't resume
    if (file.status == FileStatus.complete) {
      if (file.response != null) {
        return file.response!;
      }
      throw Exception('File already complete but no response available');
    }

    final controller = _controllers[file.id];

    if (controller != null) {
      // Check if controller is already completed before resuming
      if (controller.state == UploadState.completed) {
        // Don't call resume() or start() - just return the existing response
        // The completer should have the real result
        if (file.response != null) {
          return file.response!;
        }
        // If no response stored, wait for completer (should be instant)
        return await controller.start(); // This will return immediately if completed
      }

      // Resume existing controller
      controller.resume();
      return await controller.start(); // Continue the same upload
    } else if (file.s3Multipart.isMultipart && file.s3Multipart.uploadId != null) {
      // No controller but file has existing multipart upload - create controller in resume mode
      final controller = MultipartUploadController(
        file: file,
        options: options,
        onProgress: onProgress,
        emitEvent: emitEvent,
        dio: _dio,
        retryConfig: _retryConfig,
        shouldRetry: _shouldRetryError,
        continueExisting: true,
      );

      _controllers[file.id] = controller;

      try {
        final response = await controller.start();
        // Upload completed successfully - remove controller
        _controllers.remove(file.id);
        return response;
      } on PausedException {
        // Upload was paused - keep controller alive for resume
        rethrow;
      } catch (e) {
        // Upload errored or was cancelled - remove controller
        _controllers.remove(file.id);
        rethrow;
      }
    } else {
      // No controller and no existing upload - start new upload
      return await upload(
        file,
        onProgress: onProgress,
        emitEvent: emitEvent,
        cancellationToken: cancellationToken,
      );
    }
  }

  @override
  Future<void> cancel(FluppyFile file) async {
    final controller = _controllers[file.id];
    controller?.cancel();

    // Remove controller from map after cancellation
    _controllers.remove(file.id);

    // Abort multipart upload on server if in progress
    if (file.s3Multipart.isMultipart && file.s3Multipart.uploadId != null && file.s3Multipart.key != null) {
      try {
        await options.abortMultipartUpload(
          file,
          AbortMultipartOptions(
            uploadId: file.s3Multipart.uploadId!,
            key: file.s3Multipart.key!,
          ),
        );
      } catch (e) {
        // Ignore errors during abort
      }
    }
  }

  @override
  Future<void> resetFileState(FluppyFile file) async {
    file.resetS3Multipart();
  }

  @override
  Future<void> dispose() async {
    _controllers.clear();
    _dio.close();
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

    // Upload to S3 with retry
    final response = await withRetry(
      () async {
        cancellationToken?.throwIfCancelled();

        // Convert CancellationToken to CancelToken for dio
        CancelToken? cancelToken;
        if (cancellationToken != null) {
          cancelToken = CancelToken();
          cancellationToken.onCancel(() {
            cancelToken!.cancel();
          });
        }

        try {
          // Ensure content-type is set for binary data (Dio requirement)
          final uploadHeaders = Map<String, String>.from(params.headers ?? {});
          if (!uploadHeaders.containsKey('content-type') && !uploadHeaders.containsKey('Content-Type')) {
            uploadHeaders['Content-Type'] = file.type ?? 'application/octet-stream';
          }

          final dioResponse = await _dio.put(
            params.url,
            data: bytes,
            options: Options(
              headers: uploadHeaders,
              receiveTimeout: params.expires != null && params.expires! > 0 ? Duration(seconds: params.expires!) : null,
            ),
            cancelToken: cancelToken,
            onSendProgress: (sent, total) {
              // Report real-time progress as data is being uploaded
              onProgress(UploadProgressInfo(
                bytesUploaded: sent,
                bytesTotal: total,
              ));
            },
          );

          // Convert dio Response to http.Response-like structure
          if (dioResponse.statusCode != null && (dioResponse.statusCode! < 200 || dioResponse.statusCode! >= 300)) {
            // Check if this is an expired presigned URL
            if (S3ExpiredUrlException.isExpiredResponse(dioResponse.statusCode!, dioResponse.data?.toString())) {
              throw S3ExpiredUrlException(
                statusCode: dioResponse.statusCode,
                body: dioResponse.data?.toString(),
              );
            }
            throw S3UploadException(
              'Upload failed with status ${dioResponse.statusCode}',
              statusCode: dioResponse.statusCode,
              body: dioResponse.data?.toString(),
            );
          }

          return _DioResponseWrapper(dioResponse);
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) {
            throw CancelledException();
          }

          // Check for expired URL
          if (e.response != null &&
              S3ExpiredUrlException.isExpiredResponse(
                e.response!.statusCode ?? 0,
                e.response!.data?.toString(),
              )) {
            throw S3ExpiredUrlException(
              statusCode: e.response!.statusCode,
              body: e.response!.data?.toString(),
            );
          }

          throw S3UploadException(
            'Upload failed: ${e.message}',
            statusCode: e.response?.statusCode,
            body: e.response?.data?.toString(),
          );
        }
      },
      config: _retryConfig,
      cancellationToken: cancellationToken,
      shouldRetry: _shouldRetryError,
    );

    // Extract ETag and location
    final eTag = response.headers['etag'];
    final location = response.headers['location'] ?? params.url.split('?').first;

    return UploadResponse(
      location: location,
      eTag: eTag,
    );
  }

  /// Gets temporary credentials, using cache if valid.
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
  static Future<UploadPartBytesResult> defaultUploadPartBytes(
    UploadPartBytesOptions options,
  ) async {
    options.signal?.throwIfCancelled();

    final dio = Dio();
    try {
      // Convert CancellationToken to CancelToken
      CancelToken? cancelToken;
      if (options.signal != null) {
        cancelToken = CancelToken();
        options.signal!.onCancel(() {
          cancelToken!.cancel();
        });
      }

      // Ensure content-type is set for binary data (Dio requirement)
      final uploadHeaders = Map<String, String>.from(options.headers ?? {});
      if (!uploadHeaders.containsKey('content-type') && !uploadHeaders.containsKey('Content-Type')) {
        uploadHeaders['Content-Type'] = 'application/octet-stream';
      }

      final response = await dio.put(
        options.url,
        data: options.body,
        options: Options(
          headers: uploadHeaders,
          receiveTimeout: options.expires != null && options.expires! > 0 ? Duration(seconds: options.expires!) : null,
        ),
        cancelToken: cancelToken,
        onSendProgress: (sent, total) {
          // Report real-time progress for this part upload
          options.onProgress?.call(sent, total);
        },
      );

      if (response.statusCode != null && (response.statusCode! < 200 || response.statusCode! >= 300)) {
        if (S3ExpiredUrlException.isExpiredResponse(response.statusCode!, response.data?.toString())) {
          throw S3ExpiredUrlException(
            statusCode: response.statusCode,
            body: response.data?.toString(),
          );
        }
        throw S3UploadException(
          'Upload failed with status ${response.statusCode}',
          statusCode: response.statusCode,
          body: response.data?.toString(),
        );
      }

      // Extract ETag from Dio headers (case-insensitive)
      final eTag = response.headers.map['etag']?.first ?? response.headers.map['ETag']?.first;
      if (eTag == null) {
        throw S3UploadException(
          'No ETag in response',
          statusCode: response.statusCode,
        );
      }

      options.onComplete?.call(eTag);

      return UploadPartBytesResult(
        eTag: eTag,
        location: response.headers.map['location']?.first,
        headers: Map<String, String>.from(response.headers.map.map(
          (key, values) => MapEntry(key, values.first),
        )),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw CancelledException();
      }

      if (e.response != null &&
          S3ExpiredUrlException.isExpiredResponse(
            e.response!.statusCode ?? 0,
            e.response!.data?.toString(),
          )) {
        throw S3ExpiredUrlException(
          statusCode: e.response!.statusCode,
          body: e.response!.data?.toString(),
        );
      }

      throw S3UploadException(
        'Upload failed: ${e.message}',
        statusCode: e.response?.statusCode,
        body: e.response?.data?.toString(),
      );
    } finally {
      dio.close();
    }
  }
}

// Mixin providing retry functionality for uploaders.
mixin RetryMixin {
  /// Executes an operation with retry logic.
  Future<T> withRetry<T>(
      Future<T> Function() operation, {
        required RetryConfig config,
        required CancellationToken? cancellationToken,
        bool Function(Object error)? shouldRetry,
      }) async {
    var attempt = 0;

    while (true) {
      try {
        cancellationToken?.throwIfCancelled();
        return await operation();
      } catch (e) {
        attempt++;

        // Check if we should retry
        final canRetry = shouldRetry?.call(e) ?? _isRetryableError(e);
        if (!canRetry || attempt > config.maxRetries) {
          rethrow;
        }

        // Wait before retrying
        final delay = config.getDelay(attempt);
        await Future.delayed(delay);

        cancellationToken?.throwIfCancelled();
      }
    }
  }

  /// Default check for retryable errors.
  bool _isRetryableError(Object error) {
    // Retry on network-related errors
    final errorString = error.toString().toLowerCase();
    return errorString.contains('socket') ||
        errorString.contains('connection') ||
        errorString.contains('timeout') ||
        errorString.contains('network');
  }
}

/// Wrapper to make Dio response compatible with http.Response interface.
class _DioResponseWrapper {
  final Response _response;

  _DioResponseWrapper(this._response);

  int get statusCode => _response.statusCode ?? 0;

  String? get body => _response.data?.toString();

  Map<String, String> get headers {
    final result = <String, String>{};
    _response.headers.forEach((key, values) {
      if (values.isNotEmpty) {
        result[key] = values.first;
      }
    });
    return result;
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
class S3ExpiredUrlException extends S3UploadException {
  S3ExpiredUrlException({
    String message = 'Presigned URL has expired',
    int? statusCode,
    String? body,
  }) : super(message, statusCode: statusCode, body: body);

  /// Checks if a response indicates an expired presigned URL.
  static bool isExpiredResponse(int statusCode, String? body) {
    if (statusCode != 403) return false;
    if (body == null) return false;

    return body.contains('<Message>Request has expired</Message>') ||
        body.contains('Request has expired') ||
        body.contains('ExpiredToken') ||
        body.contains('TokenExpired');
  }

  @override
  String toString() => 'S3ExpiredUrlException: $message (status: $statusCode)';
}
