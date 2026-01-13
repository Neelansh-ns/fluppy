/// Fluppy - A modular, headless file upload library for Dart
///
/// Inspired by Uppy, Fluppy provides a flexible API for uploading files
/// to S3 and S3-compatible storage services with support for:
/// - Single-part and multipart uploads
/// - Pause, resume, and retry functionality
/// - Progress tracking
/// - Temporary credentials support
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
export 'src/s3/aws_signature_v4.dart';
export 'src/s3/fluppy_file_extension.dart' show S3FilePublic;
