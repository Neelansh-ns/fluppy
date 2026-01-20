# Fluppy

[![pub package](https://img.shields.io/pub/v/fluppy.svg)](https://pub.dev/packages/fluppy)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A modular, headless file upload library for Dart inspired by [Uppy](https://uppy.io/).

## Features

- 🚀 **S3 Uploads** - Direct uploads to S3 and S3-compatible storage
- 📦 **Multipart Support** - Automatic chunking for large files
- ⏸️ **Pause/Resume** - Full control over upload lifecycle
- 🔄 **Retry** - Automatic retry with exponential backoff
- 📊 **Progress Tracking** - Real-time upload progress events
- 🔐 **Temporary Credentials** - Support for STS tokens
- 🎯 **Headless** - Bring your own UI

## Installation

Add Fluppy to your `pubspec.yaml`:

```yaml
dependencies:
  fluppy: ^0.3.0
```

Or install via command line:

```bash
dart pub add fluppy
```

## Quick Start

### Backend Signing Mode (Default)

```dart
import 'package:fluppy/fluppy.dart';

final fluppy = Fluppy(
  uploader: S3Uploader(
    options: S3UploaderOptions(
      getUploadParameters: (file, options) async {
        // Get presigned URL from your backend
        final response = await myBackend.getPresignedUrl(file.name);
        return UploadParameters(
          method: 'PUT',
          url: response.url,
          headers: {'Content-Type': file.type ?? 'application/octet-stream'},
        );
      },
      createMultipartUpload: (file) async {
        final response = await myBackend.createMultipart(file.name);
        return CreateMultipartUploadResult(
          uploadId: response.uploadId,
          key: response.key,
        );
      },
      signPart: (file, options) async {
        final response = await myBackend.signPart(
          options.uploadId,
          options.key,
          options.partNumber,
        );
        return SignPartResult(url: response.url);
      },
      completeMultipartUpload: (file, options) async {
        final response = await myBackend.completeMultipart(
          options.uploadId,
          options.key,
          options.parts,
        );
        return CompleteMultipartResult(location: response.location);
      },
      listParts: (file, options) async {
        return await myBackend.listParts(options.uploadId, options.key);
      },
      abortMultipartUpload: (file, options) async {
        await myBackend.abortMultipart(options.uploadId, options.key);
      },
    ),
  ),
);
```

### Temporary Credentials Mode (Faster, ~20% improvement)

When using temporary credentials, Fluppy signs URLs client-side, eliminating backend signing requests:

```dart
final fluppy = Fluppy(
  uploader: S3Uploader(
    options: S3UploaderOptions(
      // Get temporary AWS credentials from your backend (STS)
      getTemporarySecurityCredentials: (options) async {
        final response = await http.get(
          Uri.parse('https://api.example.com/sts-token'),
        );
        final data = jsonDecode(response.body);
        return TemporaryCredentials.fromJson(data);
      },

      // Still need backend for S3 API operations
      createMultipartUpload: (file) async {
        final response = await myBackend.createMultipart(file.name);
        return CreateMultipartUploadResult(
          uploadId: response.uploadId,
          key: response.key,
        );
      },
      completeMultipartUpload: (file, options) async {
        final response = await myBackend.completeMultipart(
          options.uploadId,
          options.key,
          options.parts,
        );
        return CompleteMultipartResult(location: response.location);
      },
      listParts: (file, options) async {
        return await myBackend.listParts(options.uploadId, options.key);
      },
      abortMultipartUpload: (file, options) async {
        await myBackend.abortMultipart(options.uploadId, options.key);
      },

      // Optional: Custom object key generation
      getObjectKey: (file) => 'uploads/${Date.now().millisecondsSinceEpoch}-${file.name}',

      // NOTE: getUploadParameters and signPart are NOT needed when temp creds provided!
    ),
  ),
);
```

**Benefits of Temporary Credentials**:

- ~20% faster uploads (reduced request overhead)
- Reduced server load (no signing requests)
- Client-side signing using AWS Signature V4

**Security Considerations**:

- Credentials are exposed to the client (use temporary credentials only!)
- Use AWS STS to generate short-lived credentials
- Scope IAM permissions to specific bucket/operations

### Usage Example

```dart
// Add a file
final file = fluppy.addFile(FluppyFile.fromPath('/path/to/video.mp4'));

// Listen to events
fluppy.events.listen((event) {
  switch (event) {
    case FileAdded(:final file):
      print('Added: ${file.name}');
    case UploadProgress(:final file, :final progress):
      print('${file.name}: ${progress.percent.toStringAsFixed(1)}%');
    case UploadComplete(:final file, :final response):
      print('Complete: ${response?.location}');
    case UploadError(:final file, :final error):
      print('Error: $error');
    default:
      break;
  }
});

// Start upload
await fluppy.upload();
```

## API Reference

### S3UploaderOptions

| Option                            | Type                                                | Description                                                 |
| --------------------------------- | --------------------------------------------------- | ----------------------------------------------------------- |
| `shouldUseMultipart`              | `bool Function(FluppyFile)?`                        | Decide per-file whether to use multipart (default: >100MiB) |
| `limit`                           | `int`                                               | Max concurrent uploads (default: 6)                         |
| `getChunkSize`                    | `int Function(FluppyFile)?`                         | Chunk size for multipart (default: 5MiB)                    |
| `getUploadParameters`             | `Future<UploadParameters> Function(...)`            | Get presigned URL for single-part upload                    |
| `createMultipartUpload`           | `Future<CreateMultipartUploadResult> Function(...)` | Initiate multipart upload                                   |
| `signPart`                        | `Future<SignPartResult> Function(...)`              | Sign individual part                                        |
| `listParts`                       | `Future<List<S3Part>> Function(...)`                | List uploaded parts (for resume)                            |
| `abortMultipartUpload`            | `Future<void> Function(...)`                        | Abort and cleanup                                           |
| `completeMultipartUpload`         | `Future<CompleteMultipartResult> Function(...)`     | Complete upload                                             |
| `getTemporarySecurityCredentials` | `Future<TemporaryCredentials> Function(...)?`       | Get temp AWS credentials                                    |

### Control Methods

```dart
await fluppy.upload();           // Upload all files
await fluppy.upload(fileId);     // Upload specific file
await fluppy.pause(fileId);      // Pause upload
await fluppy.resume(fileId);     // Resume upload
await fluppy.retry(fileId);      // Retry failed upload
await fluppy.cancel(fileId);     // Cancel upload
fluppy.removeFile(fileId);       // Remove file from queue
```

## Examples

- **[example.dart](example/example.dart)** - Comprehensive S3 upload example with all features
- **[s3_real_app](https://github.com/Neelansh-ns/fluppy/tree/main/example/s3_real_app)** - Complete Flutter app with UI (view on GitHub)

## Documentation

- **[API Reference](https://pub.dev/documentation/fluppy/latest/)** - Full API documentation
- **[Changelog](https://github.com/Neelansh-ns/fluppy/blob/main/CHANGELOG.md)** - Version history
- **[GitHub Repository](https://github.com/Neelansh-ns/fluppy)** - Source code and issues

## Roadmap

Fluppy aims for 1:1 feature parity with [Uppy.js](https://uppy.io/). Currently implemented:

- ✅ Core orchestrator with event system
- ✅ S3 uploader (single-part and multipart)
- ✅ Pause/Resume/Retry functionality
- ✅ Progress tracking
- ✅ AWS Signature V4 support

Coming soon:

- 🔲 Tus resumable upload protocol
- 🔲 HTTP/XHR uploader
- 🔲 Preprocessing/Postprocessing pipeline
- 🔲 File restrictions (size, type, count)

## License

MIT
