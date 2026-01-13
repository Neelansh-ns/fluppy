part of 'fluppy_file_extension.dart';

/// Public S3 extension for FluppyFile.
///
/// Provides read-only access to S3 multipart upload state.
/// This extension is safe to use in your application code - the underlying
/// state is managed by the S3 uploader and cannot be modified externally.
extension S3FilePublic on FluppyFile {
  /// Whether this file is using S3 multipart upload.
  ///
  /// Returns `true` if the file is being uploaded via S3's multipart upload API,
  /// `false` otherwise (single-part upload).
  ///
  /// Example:
  /// ```dart
  /// if (file.isMultipart) {
  ///   print('${file.uploadedParts.length} parts uploaded');
  /// }
  /// ```
  bool get isMultipart {
    final state = _s3StateExpando[this];
    return state?.isMultipart ?? false;
  }

  /// List of successfully uploaded S3 parts (for multipart uploads).
  ///
  /// Returns an empty list for single-part uploads or if no parts have been uploaded yet.
  ///
  /// Example:
  /// ```dart
  /// print('Uploaded ${file.uploadedParts.length} parts');
  /// for (final part in file.uploadedParts) {
  ///   print('Part ${part.partNumber}: ${part.size} bytes');
  ///
  /// Note: To listen to part upload events, use `S3PartUploaded` event:
  /// ```dart
  /// fluppy.events.listen((event) {
  ///   if (event is S3PartUploaded) {
  ///     print('Part ${event.part.partNumber} uploaded');
  ///   }
  /// });
  /// ```
  /// }
  /// ```
  List<S3Part> get uploadedParts {
    final state = _s3StateExpando[this];
    return state?.uploadedParts ?? [];
  }
}
