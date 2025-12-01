import 'fluppy_file.dart';
import '../s3/s3_types.dart';

/// Base class for all Fluppy events.
///
/// Use pattern matching to handle events:
/// ```dart
/// fluppy.events.listen((event) {
///   switch (event) {
///     case FileAdded(:final file):
///       print('Added: ${file.name}');
///     case UploadProgress(:final file, :final progress):
///       print('${file.name}: ${progress.percent}%');
///     case UploadComplete(:final file):
///       print('Complete: ${file.name}');
///     case UploadError(:final file, :final error):
///       print('Error: $error');
///   }
/// });
/// ```
sealed class FluppyEvent {
  /// The file associated with this event.
  FluppyFile get file;

  const FluppyEvent();
}

/// Emitted when a file is added to the upload queue.
class FileAdded extends FluppyEvent {
  @override
  final FluppyFile file;

  const FileAdded(this.file);

  @override
  String toString() => 'FileAdded(${file.name})';
}

/// Emitted when a file is removed from the queue.
class FileRemoved extends FluppyEvent {
  @override
  final FluppyFile file;

  const FileRemoved(this.file);

  @override
  String toString() => 'FileRemoved(${file.name})';
}

/// Emitted when an upload starts.
class UploadStarted extends FluppyEvent {
  @override
  final FluppyFile file;

  const UploadStarted(this.file);

  @override
  String toString() => 'UploadStarted(${file.name})';
}

/// Emitted periodically during upload with progress information.
class UploadProgress extends FluppyEvent {
  @override
  final FluppyFile file;

  /// Current progress information.
  final UploadProgressInfo progress;

  const UploadProgress(this.file, this.progress);

  @override
  String toString() => 'UploadProgress(${file.name}, ${progress.percent.toStringAsFixed(1)}%)';
}

/// Emitted when an upload is paused.
class UploadPaused extends FluppyEvent {
  @override
  final FluppyFile file;

  const UploadPaused(this.file);

  @override
  String toString() => 'UploadPaused(${file.name})';
}

/// Emitted when a paused upload is resumed.
class UploadResumed extends FluppyEvent {
  @override
  final FluppyFile file;

  const UploadResumed(this.file);

  @override
  String toString() => 'UploadResumed(${file.name})';
}

/// Emitted when an upload completes successfully.
class UploadComplete extends FluppyEvent {
  @override
  final FluppyFile file;

  /// The response from the upload.
  final UploadResponse? response;

  const UploadComplete(this.file, this.response);

  @override
  String toString() => 'UploadComplete(${file.name}, ${response?.location})';
}

/// Emitted when an upload fails with an error.
class UploadError extends FluppyEvent {
  @override
  final FluppyFile file;

  /// The error that occurred.
  final Object error;

  /// Human-readable error message.
  final String message;

  const UploadError(this.file, this.error, this.message);

  @override
  String toString() => 'UploadError(${file.name}, $message)';
}

/// Emitted when an upload is cancelled.
class UploadCancelled extends FluppyEvent {
  @override
  final FluppyFile file;

  const UploadCancelled(this.file);

  @override
  String toString() => 'UploadCancelled(${file.name})';
}

/// Emitted when a retry is attempted.
class UploadRetry extends FluppyEvent {
  @override
  final FluppyFile file;

  /// The retry attempt number.
  final int attempt;

  const UploadRetry(this.file, this.attempt);

  @override
  String toString() => 'UploadRetry(${file.name}, attempt: $attempt)';
}

/// Emitted when a multipart upload part is completed.
class PartUploaded extends FluppyEvent {
  @override
  final FluppyFile file;

  /// The part that was uploaded.
  final S3Part part;

  /// Total number of parts.
  final int totalParts;

  const PartUploaded(this.file, this.part, this.totalParts);

  @override
  String toString() => 'PartUploaded(${file.name}, part ${part.partNumber}/$totalParts)';
}

/// Emitted when all uploads in the queue are complete.
class AllUploadsComplete extends FluppyEvent {
  /// Dummy file for this event - use [successful] and [failed] instead.
  @override
  FluppyFile get file => successful.isNotEmpty ? successful.first : failed.first;

  /// Files that uploaded successfully.
  final List<FluppyFile> successful;

  /// Files that failed to upload.
  final List<FluppyFile> failed;

  const AllUploadsComplete(this.successful, this.failed);

  @override
  String toString() => 'AllUploadsComplete(successful: ${successful.length}, failed: ${failed.length})';
}

/// Emitted when upload state changes (useful for UI updates).
class StateChanged extends FluppyEvent {
  @override
  final FluppyFile file;

  /// Previous status.
  final FileStatus previousStatus;

  /// New status.
  final FileStatus newStatus;

  const StateChanged(this.file, this.previousStatus, this.newStatus);

  @override
  String toString() => 'StateChanged(${file.name}, $previousStatus -> $newStatus)';
}
