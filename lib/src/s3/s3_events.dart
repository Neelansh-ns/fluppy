import '../core/fluppy.dart' show FluppyFile;
import '../core/events.dart';
import 's3_types.dart';

/// Emitted when an S3 multipart upload part is completed.
///
/// This is a plugin-specific event. Core events are defined in
/// `lib/src/core/events.dart`. Plugin events extend `FluppyEvent`
/// to integrate with the main event stream.
class S3PartUploaded extends FluppyEvent {
  @override
  final FluppyFile file;

  /// The S3 part that was uploaded.
  final S3Part part;

  /// Total number of parts.
  final int totalParts;

  const S3PartUploaded(this.file, this.part, this.totalParts);

  @override
  String toString() => 'S3PartUploaded(${file.name}, part ${part.partNumber}/$totalParts)';
}
