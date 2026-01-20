/// Fluppy - A modular, headless file upload library for Dart
///
/// Inspired by [Uppy](https://uppy.io/), Fluppy provides a flexible,
/// event-driven API for uploading files to S3 and S3-compatible storage
/// services.
///
/// ## Features
///
/// - **S3 Uploads**: Direct uploads to S3 with presigned URLs
/// - **Multipart Support**: Automatic chunking for large files
/// - **Pause/Resume**: Full control over upload lifecycle
/// - **Progress Tracking**: Real-time upload progress events
/// - **Retry Logic**: Automatic retry with exponential backoff
/// - **Headless**: Bring your own UI (works with Flutter, CLI, server)
///
/// ## Quick Start
///
/// ```dart
/// import 'package:fluppy/fluppy.dart';
///
/// final fluppy = Fluppy(
///   uploader: S3Uploader(
///     options: S3UploaderOptions(
///       getUploadParameters: (file, options) async {
///         // Get presigned URL from your backend
///         final response = await myBackend.getPresignedUrl(file.name);
///         return UploadParameters(
///           method: 'PUT',
///           url: response.url,
///           headers: {'Content-Type': file.type ?? 'application/octet-stream'},
///         );
///       },
///       // ... other callbacks for multipart uploads
///     ),
///   ),
/// );
///
/// // Add files
/// fluppy.addFile(FluppyFile.fromPath('/path/to/file.mp4'));
///
/// // Listen to events
/// fluppy.events.listen((event) {
///   switch (event) {
///     case UploadProgress(:final progress):
///       print('Progress: ${progress.percent}%');
///     case UploadComplete(:final response):
///       print('Complete: ${response?.location}');
///     default:
///       break;
///   }
/// });
///
/// // Upload
/// await fluppy.upload();
/// ```
///
/// See the [example](https://github.com/Neelansh-ns/fluppy/blob/main/example/example.dart)
/// for a complete working example with multipart uploads.
library;

// Core exports
export 'src/core/fluppy.dart';
export 'src/core/events.dart';
export 'src/core/uploader.dart';
export 'src/core/types.dart';

// S3 exports
export 'src/s3/s3_uploader.dart';
export 'src/s3/s3_options.dart';
export 'src/s3/s3_types.dart';
export 'src/s3/s3_events.dart';
export 'src/s3/s3_utils.dart';
export 'src/s3/aws_signature_v4.dart';
export 'src/s3/fluppy_file_extension.dart' show S3FilePublic;
