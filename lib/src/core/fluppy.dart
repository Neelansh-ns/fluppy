library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'types.dart';
import 'events.dart';
import 'uploader.dart';

part 'fluppy_file.dart';

/// The main Fluppy class that orchestrates file uploads.
///
/// Example usage:
/// ```dart
/// final fluppy = Fluppy(uploader: S3Uploader(options: ...));
///
/// // Add files
/// final file = fluppy.addFile(FluppyFile.fromPath('/path/to/file.mp4'));
///
/// // Listen to events
/// fluppy.events.listen((event) => print(event));
///
/// // Upload
/// await fluppy.upload();
/// ```
class Fluppy {
  /// The uploader implementation to use.
  final Uploader uploader;

  /// Configuration for retry behavior.
  final RetryConfig retryConfig;

  /// Maximum concurrent uploads.
  final int maxConcurrent;

  /// Files in the upload queue.
  final Map<String, FluppyFile> _files = {};

  /// Cancellation tokens for active uploads.
  final Map<String, CancellationToken> _cancellationTokens = {};

  /// Set of file IDs that are currently being resumed (to prevent duplicate resume calls).
  final Set<String> _resumingFiles = {};

  /// Active upload futures.
  final Map<String, Future<void>> _activeUploads = {};

  /// Event stream controller.
  final StreamController<FluppyEvent> _eventController = StreamController<FluppyEvent>.broadcast();

  /// Whether the uploader is currently running.
  bool _isUploading = false;

  /// Creates a new Fluppy instance.
  ///
  /// [uploader] - The uploader implementation (e.g., S3Uploader).
  /// [retryConfig] - Configuration for retry behavior.
  /// [maxConcurrent] - Maximum number of concurrent uploads (default: 6).
  Fluppy({
    required this.uploader,
    this.retryConfig = RetryConfig.defaultConfig,
    this.maxConcurrent = 6,
  });

  /// Stream of upload events.
  ///
  /// Listen to this stream to receive notifications about upload progress,
  /// completion, errors, etc.
  Stream<FluppyEvent> get events => _eventController.stream;

  /// All files in the queue.
  List<FluppyFile> get files => _files.values.toList();

  /// Files waiting to be uploaded.
  List<FluppyFile> get pendingFiles => _files.values.where((f) => f.status == FileStatus.pending).toList();

  /// Files currently being uploaded.
  List<FluppyFile> get uploadingFiles => _files.values.where((f) => f.status == FileStatus.uploading).toList();

  /// Files that completed successfully.
  List<FluppyFile> get completedFiles => _files.values.where((f) => f.status == FileStatus.complete).toList();

  /// Files that failed.
  List<FluppyFile> get failedFiles => _files.values.where((f) => f.status == FileStatus.error).toList();

  /// Files that are paused.
  List<FluppyFile> get pausedFiles => _files.values.where((f) => f.status == FileStatus.paused).toList();

  /// Whether any uploads are currently in progress.
  bool get isUploading => _isUploading;

  /// Gets a file by ID.
  FluppyFile? getFile(String id) => _files[id];

  /// Adds a file to the upload queue.
  ///
  /// Returns the file with a unique ID assigned.
  FluppyFile addFile(FluppyFile file) {
    _files[file.id] = file;
    _emit(FileAdded(file));
    return file;
  }

  /// Adds multiple files to the upload queue.
  List<FluppyFile> addFiles(List<FluppyFile> files) {
    return files.map(addFile).toList();
  }

  /// Removes a file from the queue.
  ///
  /// If the file is currently uploading, it will be cancelled first.
  Future<void> removeFile(String fileId) async {
    final file = _files[fileId];
    if (file == null) return;

    if (file.status == FileStatus.uploading) {
      await cancel(fileId);
    }

    _files.remove(fileId);
    _emit(FileRemoved(file));
  }

  /// Starts uploading all pending files.
  ///
  /// If [fileId] is provided, only that file will be uploaded.
  /// Returns when all uploads are complete.
  Future<void> upload([String? fileId]) async {
    if (fileId != null) {
      await _uploadFile(fileId);
      return;
    }

    _isUploading = true;

    try {
      // Upload files concurrently with a limit
      final pending = [...pendingFiles];
      final futures = <Future<void>>[];

      for (final file in pending) {
        // Wait if we're at the concurrent limit
        while (_activeUploads.length >= maxConcurrent) {
          await Future.any(_activeUploads.values);
        }

        final future = _uploadFile(file.id);
        _activeUploads[file.id] = future;
        futures.add(future.whenComplete(() => _activeUploads.remove(file.id)));
      }

      // Wait for all uploads to complete
      await Future.wait(futures);

      // Check if all uploads are complete and emit AllUploadsComplete if needed
      _checkAndEmitAllUploadsComplete();
    } finally {
      _isUploading = false;
    }
  }

  /// Uploads a single file.
  Future<void> _uploadFile(String fileId) async {
    final file = _files[fileId];
    if (file == null) return;

    if (file.status != FileStatus.pending && file.status != FileStatus.paused) {
      return;
    }

    final previousStatus = file.status;
    final cancellationToken = CancellationToken();
    _cancellationTokens[fileId] = cancellationToken;

    try {
      _updateStatus(file, FileStatus.uploading);
      _emit(UploadStarted(file));

      final response = await uploader.upload(
        file,
        onProgress: (progress) {
          file.progress = progress;
          _emit(UploadProgress(file, progress));
        },
        emitEvent: _emit,
        cancellationToken: cancellationToken,
      );

      file.response = response;
      _updateStatus(file, FileStatus.complete);
      _emit(UploadComplete(file, response));
    } on PausedException {
      // Upload was paused - ensure status is set correctly

      if (file.status != FileStatus.paused) {
        _updateStatus(file, FileStatus.paused);
        _emit(UploadPaused(file));
      }
    } on CancelledException {
      _updateStatus(file, FileStatus.cancelled);
      _emit(UploadCancelled(file));
    } catch (e) {
      final message = e.toString();
      file._updateStatusInternal(FileStatus.error, errorMsg: message, err: e);
      _emit(StateChanged(file, previousStatus, FileStatus.error));
      _emit(UploadError(file, e, message));
    } finally {
      _cancellationTokens.remove(fileId);
    }
  }

  /// Pauses an upload.
  ///
  /// Returns true if the upload was paused, false otherwise.
  Future<bool> pause(String fileId) async {
    final file = _files[fileId];
    if (file == null) return false;

    if (file.status != FileStatus.uploading) return false;

    if (!uploader.supportsPause) return false;

    // First, mark the file as paused in the uploader
    final paused = await uploader.pause(file);

    if (paused) {
      // Cancel the token to abort in-flight operations
      final token = _cancellationTokens[fileId];
      if (token != null) {
        token.cancel();
      }

      _updateStatus(file, FileStatus.paused);
      _emit(UploadPaused(file));
    }

    return paused;
  }

  /// Resumes a paused upload.
  Future<void> resume(String fileId) async {
    final file = _files[fileId];
    if (file == null) {
      return;
    }

    // Don't resume if already complete or not paused
    if (file.status != FileStatus.paused) {
      return;
    }

    // Prevent duplicate resume calls (race condition protection)
    if (_resumingFiles.contains(fileId)) {
      return;
    }

    if (!uploader.supportsResume) {
      // If resume not supported, restart from beginning
      await uploader.resetFileState(file);
      file.reset();
      await _uploadFile(fileId);
      return;
    }

    final cancellationToken = CancellationToken();
    _cancellationTokens[fileId] = cancellationToken;
    _resumingFiles.add(fileId);

    try {
      // Double-check status hasn't changed (race condition protection)
      if (file.status != FileStatus.paused) {
        return;
      }

      // Check if file already has a response OR status is complete (meaning it's complete) before emitting event
      if (file.response != null || file.status == FileStatus.complete) {
        return;
      }

      // Check if all parts are already uploaded (progress is 100%)
      // If so, don't emit UploadResumed - just complete the upload silently
      final progress = file.progress;
      bool shouldSkipResumedEvent = false;

      if (progress != null) {
        final allBytesUploaded = progress.bytesUploaded == progress.bytesTotal;
        final allPartsUploaded = progress.partsUploaded != null &&
            progress.partsTotal != null &&
            progress.partsUploaded == progress.partsTotal;

        // If all parts are uploaded, skip emitting UploadResumed.
        // This handles the case where progress reached 100% but
        // _completeUpload() hasn't been called yet.
        // For single-part uploads (no parts info), check bytes. For multipart, check parts first.
        if (progress.partsTotal != null) {
          // Multipart upload: check if all parts are uploaded
          // Use >= instead of == to handle edge cases where we might have more parts than expected
          shouldSkipResumedEvent = allPartsUploaded;
        } else {
          // Single-part upload: check bytes
          shouldSkipResumedEvent = allBytesUploaded;
        }
      }

      // Set status to uploading (needed for upload to complete properly)
      _updateStatus(file, FileStatus.uploading);

      if (shouldSkipResumedEvent && progress != null) {
        // Don't emit UploadResumed - just complete the upload silently in background
        uploader.resume(
          file,
          onProgress: (progress) {
            file.progress = progress;
            _emit(UploadProgress(file, progress));
          },
          emitEvent: _emit,
          cancellationToken: cancellationToken,
        ).then((response) {
          file.response = response;
          _updateStatus(file, FileStatus.complete);
          _emit(UploadComplete(file, response));
        }).catchError((error) {
          if (error is PausedException) {
            if (file.status != FileStatus.paused) {
              _updateStatus(file, FileStatus.paused);
              _emit(UploadPaused(file));
            }
          } else if (error is CancelledException) {
            _updateStatus(file, FileStatus.cancelled);
            _emit(UploadCancelled(file));
          } else {
            final message = error.toString();
            file._updateStatusInternal(FileStatus.error, errorMsg: message, err: error);
            _emit(UploadError(file, error, message));
          }
        });
        // Return immediately - upload completion happens in background
        return;
      } else {
        // Emit UploadResumed event
        _emit(UploadResumed(file));
      }

      // Start upload in background - don't wait for it to complete
      // Resume should return immediately after starting, not wait for completion
      uploader.resume(
        file,
        onProgress: (progress) {
          file.progress = progress;
          _emit(UploadProgress(file, progress));
        },
        emitEvent: _emit,
        cancellationToken: cancellationToken,
      ).then((response) {
        // Handle completion in background
        file.response = response;
        _updateStatus(file, FileStatus.complete);
        _emit(UploadComplete(file, response));

        // Check if all uploads are complete and emit AllUploadsComplete if needed
        _checkAndEmitAllUploadsComplete();
      }).catchError((error) {
        // Handle errors in background
        if (error is PausedException) {
          // Upload was paused - ensure status is set correctly
          if (file.status != FileStatus.paused) {
            _updateStatus(file, FileStatus.paused);
            _emit(UploadPaused(file));
          }
        } else if (error is CancelledException) {
          _updateStatus(file, FileStatus.cancelled);
          _emit(UploadCancelled(file));
        } else {
          final message = error.toString();
          file._updateStatusInternal(FileStatus.error, errorMsg: message, err: error);
          _emit(UploadError(file, error, message));
        }
      });

      // Return immediately - upload continues in background
      // Errors and completion are handled in the catchError/then callbacks above
    } finally {
      // Clean up resuming state immediately (upload continues in background)
      _cancellationTokens.remove(fileId);
      _resumingFiles.remove(fileId);
    }
  }

  /// Retries a failed upload.
  ///
  /// [attempt] is used internally for retry counting.
  Future<void> retry(String fileId, {int attempt = 1}) async {
    final file = _files[fileId];
    if (file == null) return;

    if (file.status != FileStatus.error && file.status != FileStatus.cancelled) {
      return;
    }

    _emit(UploadRetry(file, attempt));

    // Reset for retry but keep multipart state
    file.reset();
    await _uploadFile(fileId);
  }

  /// Cancels an upload.
  Future<void> cancel(String fileId) async {
    final file = _files[fileId];
    if (file == null) return;

    // Cancel the token
    final token = _cancellationTokens[fileId];
    token?.cancel();

    // Cancel in the uploader
    await uploader.cancel(file);

    if (file.status == FileStatus.uploading) {
      _updateStatus(file, FileStatus.cancelled);
      _emit(UploadCancelled(file));
    }
  }

  /// Cancels all uploads.
  Future<void> cancelAll() async {
    for (final fileId in _files.keys.toList()) {
      await cancel(fileId);
    }
  }

  /// Pauses all uploads.
  Future<void> pauseAll() async {
    for (final file in uploadingFiles) {
      await pause(file.id);
    }
  }

  /// Resumes all paused uploads.
  Future<void> resumeAll() async {
    for (final file in pausedFiles) {
      await resume(file.id);
    }
  }

  /// Retries all failed uploads.
  Future<void> retryAll() async {
    for (final file in failedFiles) {
      await retry(file.id);
    }
  }

  /// Clears completed and failed files from the queue.
  void clearCompleted() {
    _files.removeWhere(
      (_, file) =>
          file.status == FileStatus.complete || file.status == FileStatus.error || file.status == FileStatus.cancelled,
    );
  }

  /// Clears all files from the queue.
  ///
  /// Will cancel any active uploads first.
  Future<void> clearAll() async {
    await cancelAll();
    _files.clear();
  }

  /// Gets overall progress across all files.
  UploadProgressInfo get overallProgress {
    var totalBytes = 0;
    var uploadedBytes = 0;

    for (final file in _files.values) {
      totalBytes += file.size;
      uploadedBytes += file.progress?.bytesUploaded ?? 0;
    }

    return UploadProgressInfo(
      bytesUploaded: uploadedBytes,
      bytesTotal: totalBytes,
    );
  }

  /// Updates file status and emits state change event.
  void _updateStatus(FluppyFile file, FileStatus newStatus) {
    final previousStatus = file.status;
    file._setStatusInternal(newStatus);
    _emit(StateChanged(file, previousStatus, newStatus));
  }

  /// Checks if all uploads are complete and emits AllUploadsComplete if needed.
  /// This is called when uploads complete (either via upload() or resume()).
  void _checkAndEmitAllUploadsComplete() {
    // Only emit AllUploadsComplete if there are no paused or uploading files
    // (paused files should not trigger completion event)
    final pausedFiles = _files.values.where((f) => f.status == FileStatus.paused).toList();
    final stillUploading = _files.values.where((f) => f.status == FileStatus.uploading).toList();

    if (pausedFiles.isEmpty && stillUploading.isEmpty) {
      // All files are either complete or failed - emit completion event

      _emit(AllUploadsComplete(completedFiles, failedFiles));
    } else {}
  }

  /// Emits an event.
  void _emit(FluppyEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  /// Disposes of resources.
  Future<void> dispose() async {
    await cancelAll();
    await _eventController.close();
    await uploader.dispose();
  }
}
