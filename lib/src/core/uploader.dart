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

/// Configuration for retry behavior.
class RetryConfig {
  /// Maximum number of retry attempts.
  final int maxRetries;

  /// Initial delay before first retry.
  final Duration initialDelay;

  /// Maximum delay between retries.
  final Duration maxDelay;

  /// Multiplier for exponential backoff.
  final double backoffMultiplier;

  /// Explicit retry delays in milliseconds.
  ///
  /// When provided, these delays are used instead of exponential backoff.
  /// Example: `[0, 1000, 3000]` means:
  /// - First retry: immediate (0ms)
  /// - Second retry: after 1 second
  /// - Third retry: after 3 seconds
  final List<int>? retryDelays;

  const RetryConfig({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.retryDelays,
  });

  /// Calculates the delay for a given attempt number.
  Duration getDelay(int attempt) {
    if (attempt <= 0) return Duration.zero;

    // Use explicit delays if provided
    if (retryDelays != null) {
      final index = attempt - 1;
      if (index < retryDelays!.length) {
        return Duration(milliseconds: retryDelays![index]);
      }
      // If we've exhausted the delays array, use the last delay
      if (retryDelays!.isNotEmpty) {
        return Duration(milliseconds: retryDelays!.last);
      }
    }

    // Otherwise use exponential backoff
    var delay = initialDelay.inMilliseconds * (backoffMultiplier * (attempt - 1)).ceil();

    if (delay > maxDelay.inMilliseconds) {
      delay = maxDelay.inMilliseconds;
    }

    return Duration(milliseconds: delay);
  }

  /// Default retry configuration.
  static const defaultConfig = RetryConfig();
}

/// Mixin providing retry functionality for uploaders.
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
