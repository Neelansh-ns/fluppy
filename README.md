# Fluppy

A modular, headless file upload library for Dart inspired by [Uppy](https://uppy.io/).

## Features

-   🚀 **S3 Uploads** - Direct uploads to S3 and S3-compatible storage
-   📦 **Multipart Support** - Automatic chunking for large files
-   ⏸️ **Pause/Resume** - Full control over upload lifecycle
-   🔄 **Retry** - Automatic retry with exponential backoff
-   📊 **Progress Tracking** - Real-time upload progress events
-   🔐 **Temporary Credentials** - Support for STS tokens
-   🎯 **Headless** - Bring your own UI

## Installation

```yaml
dependencies:
    fluppy: ^0.1.0
```

## Quick Start

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

## License

MIT
