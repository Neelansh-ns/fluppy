## 0.2.0 - 2026-01-14

### Changed

**Documentation Improvements**
- Enhanced README.md with pub.dev and license badges
- Added command-line installation instructions
- Added comprehensive Examples and Documentation sections
- Added Roadmap section showing current features and future plans
- Expanded CHANGELOG.md with detailed feature descriptions
- Enhanced library-level documentation (lib/fluppy.dart) with Quick Start example
- Improved API documentation with better examples and links

**Package Publishing**
- Fixed dartdoc warnings for better API documentation quality
- Created .pubignore to exclude internal documentation from published package
- Updated repository URLs from placeholder to actual GitHub repository
- Reduced published package size from ~350KB to 48KB

### Fixed
- Removed unresolved dartdoc reference to `[retryConfig]` parameter
- Fixed dartdoc syntax for list examples in S3UploaderOptions

## 0.1.0 - 2026-01-13

First stable release of Fluppy, a modular file upload library for Dart inspired by Uppy.

### Features

**Core Upload System**
- Event-driven architecture with type-safe sealed class events
- Support for multiple concurrent uploads (configurable limit)
- File queue management (add, remove, pause, resume, retry, cancel)
- Multiple file sources: path, bytes, stream
- Comprehensive progress tracking with percentage and byte counts
- Automatic retry with exponential backoff
- Clean separation between core and uploader implementations

**S3 Uploader**
- Single-part uploads with presigned URLs
- Multipart uploads for large files (>100 MiB default threshold)
- Automatic chunking with configurable chunk size (5 MiB minimum)
- Pause/resume functionality for interrupted uploads
- Part upload tracking and resume from last uploaded part
- AWS Signature V4 support for direct S3 access
- Temporary security credentials (STS) support
- Configurable concurrent part uploads
- Automatic abort on cancellation with cleanup

**Developer Experience**
- Fully typed Dart API with null safety
- Comprehensive dartdoc documentation
- Headless design (bring your own UI)
- Stream-based event system with pattern matching
- Works with Flutter, Dart CLI, and server-side Dart
- Example code demonstrating common use cases
- Extensive test coverage

### Breaking Changes

N/A - First stable release (from 0.0.1 development version)

### Known Limitations

- Only S3-compatible storage supported (Tus, HTTP uploaders planned)
- No preprocessing/postprocessing pipeline (planned for future release)
- No file validation/restrictions (planned for future release)
- No UI components (intentionally headless)

## 0.0.1

- Initial development release
