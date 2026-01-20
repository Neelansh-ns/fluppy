// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:fluppy/fluppy.dart';

/// Example demonstrating Fluppy S3 uploads.
///
/// This example shows how to:
/// - Configure S3 uploads with presigned URLs
/// - Handle upload events
/// - Use pause/resume/retry functionality
void main() async {
  // Create a Fluppy instance with S3 uploader
  final fluppy = Fluppy(
    uploader: S3Uploader(
      options: S3UploaderOptions(
        // Decide whether to use multipart based on file size
        shouldUseMultipart: (file) => file.size > 100 * 1024 * 1024, // 100 MiB

        // Chunk size for multipart uploads (minimum 5 MiB)
        getChunkSize: (file) => 10 * 1024 * 1024, // 10 MiB

        // Get presigned URL for single-part uploads
        getUploadParameters: (file, options) async {
          // In a real app, call your backend to get a presigned URL
          // Example:
          // final response = await http.post(
          //   Uri.parse('https://api.example.com/upload/presign'),
          //   body: jsonEncode({'filename': file.name, 'contentType': file.type}),
          // );
          // final data = jsonDecode(response.body);

          return UploadParameters(
            method: 'PUT',
            url: 'https://your-bucket.s3.amazonaws.com/${file.name}?presigned-params',
            headers: {
              'Content-Type': file.type ?? 'application/octet-stream',
            },
          );
        },

        // Initiate multipart upload
        createMultipartUpload: (file) async {
          // Call your backend to initiate multipart upload
          // This typically calls S3's CreateMultipartUpload API

          return CreateMultipartUploadResult(
            uploadId: 'example-upload-id',
            key: 'uploads/${file.name}',
          );
        },

        // Sign each part
        signPart: (file, options) async {
          // Call your backend to get a presigned URL for this part
          // The backend should use S3's UploadPart presigning

          return SignPartResult(
            url: 'https://your-bucket.s3.amazonaws.com/${options.key}'
                '?partNumber=${options.partNumber}'
                '&uploadId=${options.uploadId}'
                '&presigned-params',
            headers: {
              'Content-Type': 'application/octet-stream',
            },
          );
        },

        // List already uploaded parts (for resume)
        listParts: (file, options) async {
          // Call your backend to list parts
          // This is used when resuming an interrupted upload

          return <S3Part>[];
        },

        // Abort multipart upload
        abortMultipartUpload: (file, options) async {
          // Call your backend to abort the multipart upload
          // This cleans up uploaded parts from S3
        },

        // Complete multipart upload
        completeMultipartUpload: (file, options) async {
          // Call your backend to complete the upload
          // This combines all parts into the final object
          //
          // Note: Fluppy returns raw location URLs (matching Uppy.js behavior).
          // If your backend doesn't return a location, or you need a decoded URL,
          // you can use S3Utils helpers:
          //
          // Option 1: Backend returns location (recommended)
          //   return CompleteMultipartResult(location: response.url, body: {...});
          //
          // Option 2: Construct URL using S3Utils if backend doesn't return one
          //   final location = S3Utils.constructUrl(
          //     bucket: 'your-bucket',
          //     region: 'us-east-1',
          //     key: options.key,
          //   );
          //
          // Option 3: Decode URL for cleaner display (optional)
          //   final displayUrl = S3Utils.decodeUrlPath(response.url);

          // You can pass custom data through the body field
          // This data will be available in the UploadComplete event
          return CompleteMultipartResult(
            location: 'https://your-bucket.s3.amazonaws.com/uploads/${file.name}',
            body: {
              // Pass any custom data from your backend response
              'mediaId': 'generated-media-id-12345',
              'blobId': 'blob-reference-abc',
              // You can include any application-specific data here
            },
          );
        },

        // Optional: Get temporary credentials for client-side signing
        // When provided, getUploadParameters and signPart are NOT called
        // Fluppy signs URLs client-side instead, reducing backend round-trips by ~20%
        // getTemporarySecurityCredentials: (options) async {
        //   // Call your backend to get temporary AWS credentials from STS
        //   final response = await http.get(
        //     Uri.parse('https://api.example.com/sts-token'),
        //   );
        //   final data = jsonDecode(response.body);
        //   // Expected format: { credentials: { AccessKeyId, SecretAccessKey, SessionToken, Expiration }, bucket, region }
        //   return TemporaryCredentials.fromJson(data);
        // },

        // Optional: Custom object key generation (defaults to file.name)
        // getObjectKey: (file) => 'uploads/${DateTime.now().millisecondsSinceEpoch}/${file.name}',
      ),
    ),
    maxConcurrent: 3, // Max 3 concurrent file uploads
  );

  // Listen to upload events
  fluppy.events.listen((event) {
    switch (event) {
      case FileAdded(:final file):
        print('📁 Added: ${file.name}');

      case UploadStarted(:final file):
        print('🚀 Started: ${file.name}');

      case UploadProgress(:final file, :final progress):
        final percent = progress.percent.toStringAsFixed(1);
        final uploaded = _formatBytes(progress.bytesUploaded);
        final total = _formatBytes(progress.bytesTotal);
        print('📊 ${file.name}: $percent% ($uploaded / $total)');

      case S3PartUploaded(:final file, :final part, :final totalParts):
        print('   ${file.name}: Part ${part.partNumber}/$totalParts uploaded');

      case UploadPaused(:final file):
        print('⏸️  Paused: ${file.name}');

      case UploadResumed(:final file):
        print('▶️  Resumed: ${file.name}');

      case UploadComplete(:final file, :final response):
        print('✅ Complete: ${file.name}');
        // Note: location is returned raw (may be URL-encoded) like Uppy.js
        // Use S3Utils.decodeUrlPath() if you want a decoded URL for display
        final location = response?.location;
        if (location != null) {
          print('   Location: $location');
          // Optional: decode for cleaner display
          // print('   Display URL: ${S3Utils.decodeUrlPath(location)}');
        }
        // Access custom data from response body
        final mediaId = response?.body?['mediaId'];
        final eTag = response?.body?['eTag'];
        if (mediaId != null) print('   Media ID: $mediaId');
        if (eTag != null) print('   ETag: $eTag');

      case UploadError(:final file, :final message):
        print('❌ Error: ${file.name} - $message');

      case UploadCancelled(:final file):
        print('🚫 Cancelled: ${file.name}');

      case UploadRetry(:final file, :final attempt):
        print('🔄 Retry #$attempt: ${file.name}');

      case AllUploadsComplete(:final successful, :final failed):
        print('');
        print('=== All uploads complete ===');
        print('✅ Successful: ${successful.length}');
        print('❌ Failed: ${failed.length}');

      default:
        break;
    }
  });

  // Add files to upload
  // From path
  if (File('example.txt').existsSync()) {
    fluppy.addFile(FluppyFile.fromPath('example.txt'));
  }

  // From bytes
  fluppy.addFile(FluppyFile.fromBytes(
    Uint8List.fromList('Hello, World!'.codeUnits),
    name: 'hello.txt',
    type: 'text/plain',
  ));

  // Check files in queue
  print('Files in queue: ${fluppy.files.length}');

  // Start uploading
  print('Starting uploads...\n');
  await fluppy.upload();

  // Cleanup
  await fluppy.dispose();
}

/// Example of pause/resume flow
Future<void> pauseResumeExample(Fluppy fluppy, String fileId) async {
  // Start upload in background
  final uploadFuture = fluppy.upload(fileId);

  // Wait a bit then pause
  await Future.delayed(const Duration(seconds: 2));
  await fluppy.pause(fileId);
  print('Upload paused');

  // Wait then resume
  await Future.delayed(const Duration(seconds: 1));
  await fluppy.resume(fileId);
  print('Upload resumed');

  await uploadFuture;
}

/// Example of retry flow
Future<void> retryExample(Fluppy fluppy, String fileId) async {
  try {
    await fluppy.upload(fileId);
  } catch (e) {
    print('Upload failed, retrying...');
    await fluppy.retry(fileId);
  }
}

/// Format bytes to human readable string
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
