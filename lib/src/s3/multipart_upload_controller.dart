import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart' hide ProgressCallback;

import '../core/fluppy.dart' show FluppyFile;
import '../core/types.dart';
import '../core/uploader.dart';
import 'aws_signature_v4.dart';
import 'fluppy_file_extension.dart';
import 's3_events.dart';
import 's3_options.dart';
import 's3_types.dart';
import 's3_uploader.dart';

/// Controller for managing a single multipart upload lifecycle.
///
/// The controller stays alive during pause. Pause aborts operations with a special reason,
/// resume continues the same upload.
///
/// State machine: idle → running → paused → running → completed
class MultipartUploadController {
  final FluppyFile file;
  final S3UploaderOptions options;
  final ProgressCallback onProgress;
  final EventEmitter emitEvent;
  final Dio dio;
  final RetryConfig retryConfig;
  final bool Function(Object error) shouldRetry;

  /// Function to get temporary credentials (if available).
  /// Returns null if temp creds not configured or unavailable.
  final Future<TemporaryCredentials?> Function({CancellationToken? cancellationToken})? getTemporaryCredentials;

  // State
  UploadState _state = UploadState.idle;
  CancelToken? _cancelToken;
  final Completer<UploadResponse> _completer = Completer();

  /// Whether the upload has been started (first time).
  bool _uploadStarted = false;

  /// Track progress for each part during upload (partNumber -> bytes uploaded for that part).
  final Map<int, int> _partProgress = {};

  /// Track total bytes already uploaded (from completed parts).
  int _uploadedBytes = 0;

  /// Track which parts have completed to prevent double-counting from late onSendProgress callbacks.
  final Set<int> _completedParts = {};

  /// Special reason for pausing (not a real error).
  static const String _pausingReason = 'pausing upload, not an actual error';

  MultipartUploadController({
    required this.file,
    required this.options,
    required this.onProgress,
    required this.emitEvent,
    required this.dio,
    required this.retryConfig,
    required this.shouldRetry,
    this.getTemporaryCredentials,
    bool continueExisting = false,
  }) : _uploadStarted = continueExisting;

  UploadState get state => _state;

  /// Starts or resumes the upload.
  ///
  /// Returns a Future that completes when the upload is finished.
  Future<UploadResponse> start() async {
    // If already completed, return the existing result
    if (_state == UploadState.completed && _completer.isCompleted) {
      return _completer.future;
    }

    if (_state == UploadState.cancelled) {
      throw CancelledException();
    }

    if (_uploadStarted) {
      // Resume: abort any pending operations and restart
      if (_cancelToken != null && !_cancelToken!.isCancelled) {
        _cancelToken!.cancel(_pausingReason);
      }
      _cancelToken = CancelToken();
      await _resumeUpload();

      // Check if paused after resume attempt
      if (_state == UploadState.paused) {
        throw PausedException();
      }
    } else {
      // First start
      _cancelToken = CancelToken();
      await _startUpload();

      // Check if paused after start attempt
      if (_state == UploadState.paused) {
        throw PausedException();
      }
    }

    return _completer.future;
  }

  /// Pauses the upload.
  ///
  /// Aborts current operations with special reason, creates new token for resume.
  void pause() {
    if (_state == UploadState.completed || _state == UploadState.cancelled) {
      return;
    }

    _state = UploadState.paused;
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _cancelToken!.cancel(_pausingReason);
    }
    _cancelToken = CancelToken(); // New token for resume
  }

  /// Resumes the upload.
  ///
  /// Changes state to running. Call start() to continue.
  void resume() {
    if (_state == UploadState.completed || _state == UploadState.cancelled) {
      return;
    }

    _state = UploadState.running;
  }

  /// Cancels the upload permanently.
  void cancel() {
    if (_state == UploadState.completed) {
      return;
    }

    _state = UploadState.cancelled;
    _cancelToken?.cancel();

    if (!_completer.isCompleted) {
      _completer.completeError(CancelledException());
    }
  }

  /// Starts the upload for the first time.
  Future<void> _startUpload() async {
    _state = UploadState.running;
    _uploadStarted = true;

    try {
      // Create multipart upload

      final result = await options.createMultipartUpload(file);

      file.s3Multipart.uploadId = result.uploadId;
      file.s3Multipart.key = result.key;
      file.s3Multipart.isMultipart = true;

      // Upload parts
      await _uploadParts();

      // Complete
      final response = await _completeUpload();

      _state = UploadState.completed;
      if (!_completer.isCompleted) {
        _completer.complete(response);
      }
    } catch (e) {
      if (_isPausingError(e)) {
        // This is a pause, not an error - wait for resume
        return;
      }

      _state = UploadState.error;
      if (!_completer.isCompleted) {
        _completer.completeError(e);
      }
    }
  }

  /// Resumes the upload after being paused.
  Future<void> _resumeUpload() async {
    // If already completed, don't resume
    if (_state == UploadState.completed && _completer.isCompleted) {
      return;
    }

    _state = UploadState.running;

    try {
      // List parts from S3 (source of truth)
      final existingParts = await options.listParts(
        file,
        ListPartsOptions(
          uploadId: file.s3Multipart.uploadId!,
          key: file.s3Multipart.key!,
          signal: _createCancellationToken(),
        ),
      );

      // Replace in-memory state with S3 reality
      file.s3Multipart.uploadedParts.clear();
      file.s3Multipart.uploadedParts.addAll(existingParts);

      // Upload remaining parts
      await _uploadParts();

      // Complete
      final response = await _completeUpload();

      _state = UploadState.completed;
      if (!_completer.isCompleted) {
        _completer.complete(response);
      }
    } catch (e) {
      if (_isPausingError(e)) {
        // This is a pause, not an error - convert to PausedException so fluppy.resume() can handle it

        // Set state back to paused
        _state = UploadState.paused;
        // Throw PausedException so fluppy.resume() can catch it and handle properly
        throw PausedException();
      }

      _state = UploadState.error;
      if (!_completer.isCompleted) {
        _completer.completeError(e);
      }
    }
  }

  /// Uploads all remaining parts.
  Future<void> _uploadParts() async {
    if (_state == UploadState.paused) {
      throw CancelledException(_pausingReason);
    }

    final chunkSize = options.chunkSize(file);
    final totalParts = (file.size / chunkSize).ceil();

    // Calculate already uploaded bytes
    var uploadedBytes = file.s3Multipart.uploadedParts.fold<int>(
      0,
      (sum, part) => sum + part.size,
    );

    // Initialize tracking for completed bytes (used for progress aggregation)
    _uploadedBytes = uploadedBytes;
    _partProgress.clear(); // Clear any stale progress from previous attempts
    _completedParts.clear(); // Clear completed parts tracking

    // Find parts that need uploading
    final uploadedPartNumbers = file.s3Multipart.uploadedParts.map((p) => p.partNumber).toSet();
    final partsToUpload = <int>[];
    for (int i = 1; i <= totalParts; i++) {
      if (!uploadedPartNumbers.contains(i)) {
        partsToUpload.add(i);
      }
    }

    // If all parts are already uploaded, skip uploading
    if (partsToUpload.isEmpty) {
      return;
    }

    // Report initial progress using aggregated method
    _emitAggregatedProgress();

    // If no parts to upload, we're done
    if (partsToUpload.isEmpty) {
      return;
    }

    // Upload parts with concurrency limit
    final semaphore = _Semaphore(options.maxConcurrentParts);
    final futures = <Future<void>>[];

    for (final partNumber in partsToUpload) {
      if (_state == UploadState.paused) {
        throw CancelledException(_pausingReason);
      }

      final future = semaphore.run(() async {
        if (_state == UploadState.paused) {
          throw CancelledException(_pausingReason);
        }

        final part = await _uploadPart(partNumber, chunkSize, totalParts);

        // Only add part if still in running state
        if (_state == UploadState.running) {
          // Check for duplicate (shouldn't happen, but be safe)
          final alreadyExists = file.s3Multipart.uploadedParts.any((p) => p.partNumber == part.partNumber);
          if (!alreadyExists) {
            file.s3Multipart.uploadedParts.add(part);
            uploadedBytes += part.size;

            // Note: _uploadedBytes already updated in _uploadPart to prevent gap

            // Report aggregated progress (includes both completed and in-flight parts)
            _emitAggregatedProgress();

            emitEvent(S3PartUploaded(file, part, totalParts));
          }
        }
      });

      futures.add(future);
    }

    await Future.wait(futures);
  }

  /// Uploads a single part with retry.
  Future<S3Part> _uploadPart(
    int partNumber,
    int chunkSize,
    int totalParts,
  ) async {
    // Calculate byte range for this part
    final start = (partNumber - 1) * chunkSize;
    var end = start + chunkSize;
    if (end > file.size) {
      end = file.size;
    }

    // Get chunk data
    final chunkData = await file.getChunk(start, end);

    _throwIfCancelled();

    // Sign the part - use temp creds if available, otherwise fall back to backend callback
    SignPartResult signResult;

    if (getTemporaryCredentials != null && options.getTemporarySecurityCredentials != null) {
      // Get temporary credentials (cached if valid)
      final credentials = await getTemporaryCredentials!(
        cancellationToken: _createCancellationToken(),
      );

      if (credentials != null) {
        // Sign part URL client-side using temporary credentials (via extension method)
        signResult = credentials.createPresignedPartUrl(
          key: file.s3Multipart.key!,
          uploadId: file.s3Multipart.uploadId!,
          partNumber: partNumber,
          expires: 3600, // 1 hour default expiration
        );
      } else {
        // Temp creds unavailable, fall back to backend signing
        signResult = await options.signPart(
          file,
          SignPartOptions(
            uploadId: file.s3Multipart.uploadId!,
            key: file.s3Multipart.key!,
            partNumber: partNumber,
            body: chunkData,
            signal: _createCancellationToken(),
          ),
        );
      }
    } else {
      // No temp creds configured, use backend signing
      signResult = await options.signPart(
        file,
        SignPartOptions(
          uploadId: file.s3Multipart.uploadId!,
          key: file.s3Multipart.key!,
          partNumber: partNumber,
          body: chunkData,
          signal: _createCancellationToken(),
        ),
      );
    }

    _throwIfCancelled();

    // Upload the part with retry

    final uploadResult = await _withRetry(
      () => _doUploadPartBytes(
        url: signResult.url,
        data: chunkData,
        partNumber: partNumber,
        headers: signResult.headers,
        expires: signResult.expires,
      ),
    );

    // All tracking (_uploadedBytes, _completedParts, _partProgress) already updated
    // in _uploadPartData/_doUploadPartBytes to prevent gaps
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
    required int partNumber,
    Map<String, String>? headers,
    int? expires,
  }) async {
    _throwIfCancelled();

    // Use custom callback if provided
    if (options.uploadPartBytes != null) {
      final result = await options.uploadPartBytes!(
        UploadPartBytesOptions(
          url: url,
          headers: headers,
          body: data,
          size: data.length,
          expires: expires,
          signal: _createCancellationToken(),
          onProgress: (sent, total) {
            _updatePartProgress(partNumber, sent);
          },
          onComplete: (eTag) {
            // Part completed, progress already tracked
          },
        ),
      );

      // Update tracking atomically IMMEDIATELY after custom callback returns
      // This prevents gap where bytes are in neither _partProgress nor _uploadedBytes
      final partSize = data.length;
      _completedParts.add(partNumber);
      _partProgress.remove(partNumber);
      _uploadedBytes += partSize;

      return result;
    }

    // Use default implementation with dio
    return await _uploadPartData(
      url,
      data,
      partNumber,
      headers,
      expires: expires,
    );
  }

  /// Uploads part data using dio (supports cancellation).
  Future<UploadPartBytesResult> _uploadPartData(
    String url,
    Uint8List data,
    int partNumber,
    Map<String, String>? headers, {
    int? expires,
  }) async {
    _throwIfCancelled();

    try {
      // Ensure content-type is set for binary data (Dio requirement)
      final uploadHeaders = Map<String, String>.from(headers ?? {});
      if (!uploadHeaders.containsKey('content-type') && !uploadHeaders.containsKey('Content-Type')) {
        uploadHeaders['Content-Type'] = 'application/octet-stream';
      }

      final response = await dio.put(
        url,
        data: data,
        options: Options(
          headers: uploadHeaders,
          receiveTimeout: expires != null && expires > 0 ? Duration(seconds: expires) : null,
        ),
        cancelToken: _cancelToken,
        onSendProgress: (sent, total) {
          // Report real-time progress for this part
          _updatePartProgress(partNumber, sent);
        },
      );

      // Update tracking atomically IMMEDIATELY after dio.put returns
      // This prevents gap where bytes are in neither _partProgress nor _uploadedBytes
      final partSize = data.length;
      _completedParts.add(partNumber);
      _partProgress.remove(partNumber);
      _uploadedBytes += partSize;

      // Dio headers are case-insensitive but stored as Map<String, List<String>>
      final headersMap = response.headers.map;
      final eTag = headersMap['etag']?.first ?? headersMap['ETag']?.first;
      final locationHeader = headersMap['location']?.first ?? headersMap['Location']?.first;

      if (eTag == null) {
        throw S3UploadException(
          'No ETag in response',
          statusCode: response.statusCode,
        );
      }

      // Convert headers map to String map
      final headersStringMap = <String, String>{};
      headersMap.forEach((key, values) {
        if (values.isNotEmpty) {
          headersStringMap[key] = values.first;
        }
      });

      return UploadPartBytesResult(
        eTag: eTag,
        location: locationHeader,
        headers: headersStringMap,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        // Check if this is a pause or real cancel
        // DioException cancel error is stored in e.error, not e.message
        final cancelError = e.error?.toString() ?? '';

        if (cancelError.contains(_pausingReason) || e.message == _pausingReason) {
          throw CancelledException(_pausingReason);
        }
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
        'Part upload failed: ${e.message}',
        statusCode: e.response?.statusCode,
        body: e.response?.data?.toString(),
      );
    }
  }

  /// Completes the multipart upload.
  Future<UploadResponse> _completeUpload() async {
    _throwIfCancelled();

    // Sort parts by part number
    final sortedParts = List<S3Part>.from(file.s3Multipart.uploadedParts)
      ..sort((a, b) => a.partNumber.compareTo(b.partNumber));

    final result = await options.completeMultipartUpload(
      file,
      CompleteMultipartOptions(
        uploadId: file.s3Multipart.uploadId!,
        key: file.s3Multipart.key!,
        parts: sortedParts,
        signal: _createCancellationToken(),
      ),
    );

    // Emit final progress update (100%) before completing
    _emitAggregatedProgress();

    return UploadResponse(
      location: result.location,
      eTag: result.eTag,
      key: file.s3Multipart.key,
    );
  }

  /// Executes an operation with retry logic.
  Future<T> _withRetry<T>(Future<T> Function() operation) async {
    var attempt = 0;

    while (true) {
      try {
        _throwIfCancelled();
        return await operation();
      } catch (e) {
        attempt++;

        // Don't retry pause/cancel errors
        if (_isPausingError(e) || e is CancelledException) {
          rethrow;
        }

        // Check if we should retry
        final canRetry = shouldRetry(e);
        if (!canRetry || attempt > retryConfig.maxRetries) {
          rethrow;
        }

        // Wait before retrying
        final delay = retryConfig.getDelay(attempt);
        await Future.delayed(delay);

        _throwIfCancelled();
      }
    }
  }

  /// Checks if error is from pausing (not a real error).
  bool _isPausingError(Object error) {
    if (error is CancelledException) {
      final isPause = error.message == _pausingReason;

      return isPause;
    }
    if (error is DioException) {
      final cancelError = error.error?.toString() ?? '';
      final isPause = error.type == DioExceptionType.cancel &&
          (cancelError.contains(_pausingReason) || error.message == _pausingReason);

      return isPause;
    }
    return false;
  }

  /// Throws if cancelled.
  void _throwIfCancelled() {
    if (_cancelToken?.isCancelled ?? false) {
      // Check if this is a pause or real cancel
      final error = _cancelToken!.cancelError;
      final errorString = error?.toString() ?? '';
      if (errorString == _pausingReason || errorString.contains(_pausingReason)) {
        throw CancelledException(_pausingReason);
      }
      throw CancelledException();
    }
    if (_state == UploadState.cancelled) {
      throw CancelledException();
    }
  }

  /// Creates a CancellationToken from the current CancelToken.
  ///
  /// Note: This creates a token that checks the dio CancelToken before operations.
  /// The actual cancellation check happens via _throwIfCancelled().
  CancellationToken _createCancellationToken() {
    final token = CancellationToken();
    // If dio token is already cancelled, cancel our token too
    if (_cancelToken?.isCancelled ?? false) {
      token.cancel();
    }
    return token;
  }

  /// Emits aggregated progress (completed + in-flight parts).
  ///
  /// This is the SINGLE SOURCE of progress reporting to prevent mixing
  /// completed-only and real-time progress values.
  void _emitAggregatedProgress() {
    // Calculate total in-progress bytes across all active parts
    final inProgressBytes = _partProgress.values.fold<int>(0, (sum, bytes) => sum + bytes);

    // Total progress = completed parts + in-progress parts
    final totalProgress = _uploadedBytes + inProgressBytes;

    // Calculate parts info
    final chunkSize = options.chunkSize(file);
    final totalParts = (file.size / chunkSize).ceil();

    // Clamp to file size to prevent > 100% (edge case with rounding)
    final bytesUploaded = totalProgress.clamp(0, file.size);

    // Report aggregated progress
    onProgress(UploadProgressInfo(
      bytesUploaded: bytesUploaded,
      bytesTotal: file.size,
      partsUploaded: file.s3Multipart.uploadedParts.length,
      partsTotal: totalParts,
    ));
  }

  /// Updates progress for a specific part and reports aggregated progress.
  void _updatePartProgress(int partNumber, int bytesUploaded) {
    // Ignore progress updates for parts that have already completed
    // This prevents double-counting from late onSendProgress callbacks
    if (_completedParts.contains(partNumber)) {
      return;
    }

    // Make progress monotonic - prevent regressions from out-of-order callbacks
    final prev = _partProgress[partNumber] ?? 0;
    final next = bytesUploaded > prev ? bytesUploaded : prev;
    _partProgress[partNumber] = next;

    // Emit aggregated progress from single source
    _emitAggregatedProgress();
  }
}

/// State of a multipart upload.
enum UploadState {
  idle,
  running,
  paused,
  cancelled,
  completed,
  error,
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
