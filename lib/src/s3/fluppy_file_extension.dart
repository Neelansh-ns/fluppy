import '../core/fluppy.dart' show FluppyFile;
import 's3_types.dart' show S3Part, S3MultipartState;
import 'package:meta/meta.dart';

part 'fluppy_file_extension_public.dart';

/// Private storage for S3 multipart state.
/// Shared between internal and public extensions via part files.
final _s3StateExpando = Expando<S3MultipartState>('s3MultipartState');

/// Internal S3 extension for FluppyFile.
///
/// Provides full read-write access to S3 state for the S3 uploader.
extension S3FileState on FluppyFile {
  /// Internal accessor for S3 uploader (creates state if needed).
  ///
  /// **⚠️ INTERNAL**: This is used by S3Uploader only.
  @internal
  S3MultipartState get s3Multipart {
    var state = _s3StateExpando[this];
    if (state == null) {
      state = S3MultipartState();
      _s3StateExpando[this] = state;
    }
    return state;
  }

  /// Resets S3 multipart state.
  ///
  /// **⚠️ INTERNAL**: Used by S3Uploader.resetFileState() only.
  @internal
  void resetS3Multipart() {
    _s3StateExpando[this]?.reset();
  }
}
