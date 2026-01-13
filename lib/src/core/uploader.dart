import 'dart:async';

import 'fluppy.dart' show FluppyFile;
import 'events.dart';
import 'types.dart';

/// Callback type for progress updates.
typedef ProgressCallback = void Function(UploadProgressInfo progress);

/// Callback type for emitting events.
typedef EventEmitter = void Function(FluppyEvent event);

/// Abstract base class for upload implementations.
///
/// Extend this class to create custom uploaders (e.g., S3, Tus, etc.)
abstract class Uploader {
  /// Uploads a file.
  ///
  /// [file] - The file to upload.
  /// [onProgress] - Callback for progress updates.
  /// [emitEvent] - Callback to emit events.
  /// [cancellationToken] - Token to check for cancellation.
  ///
  /// Returns the upload response on success.
  /// Throws on failure.
  Future<UploadResponse> upload(
    FluppyFile file, {
    required ProgressCallback onProgress,
    required EventEmitter emitEvent,
    CancellationToken? cancellationToken,
  });

  /// Pauses an upload.
  ///
  /// Returns true if the upload was paused, false if not supported or already paused.
  Future<bool> pause(FluppyFile file);

  /// Resumes a paused upload.
  ///
  /// [file] - The file to resume.
  /// [onProgress] - Callback for progress updates.
  /// [emitEvent] - Callback to emit events.
  /// [cancellationToken] - Token to check for cancellation.
  ///
  /// Returns the upload response on success.
  Future<UploadResponse> resume(
    FluppyFile file, {
    required ProgressCallback onProgress,
    required EventEmitter emitEvent,
    CancellationToken? cancellationToken,
  });

  /// Cancels an upload.
  ///
  /// Should clean up any resources and abort any ongoing requests.
  Future<void> cancel(FluppyFile file);

  /// Resets uploader-specific state on a file.
  ///
  /// Called when an upload needs to be restarted from the beginning
  /// (e.g., when resume is not supported). The uploader should clear
  /// any state it has stored on the file object.
  Future<void> resetFileState(FluppyFile file) async {
    // Default: no-op. Uploaders with state should override.
  }

  /// Checks if this uploader supports pausing.
  bool get supportsPause;

  /// Checks if this uploader supports resuming.
  bool get supportsResume;

  /// Disposes of any resources held by the uploader.
  Future<void> dispose();
}
