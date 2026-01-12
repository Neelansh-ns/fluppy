import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';
import 'package:fluppy/fluppy.dart';

void main() {
  late HttpServer server;
  late String baseUrl;
  late MockS3Server mockS3;

  setUp(() async {
    mockS3 = MockS3Server();
    server = await io.serve(mockS3.handler, 'localhost', 0);
    baseUrl = 'http://localhost:${server.port}';
  });

  tearDown(() async {
    await server.close();
    mockS3.reset();
  });

  group('S3 Integration Tests - Single-Part Upload', () {
    test('complete single-part upload flow with real HTTP', () async {
      final uploader = S3Uploader(
        options: S3UploaderOptions(
          shouldUseMultipart: (file) => false,
          getUploadParameters: (file, opts) async {
            return UploadParameters(
              method: 'PUT',
              url: '$baseUrl/bucket/${file.name}',
              headers: {
                'Content-Type': file.type ?? 'application/octet-stream',
              },
            );
          },
          createMultipartUpload: (file) => throw UnimplementedError(),
          signPart: (file, opts) => throw UnimplementedError(),
          listParts: (file, opts) => throw UnimplementedError(),
          completeMultipartUpload: (file, opts) => throw UnimplementedError(),
          abortMultipartUpload: (file, opts) async {},
        ),
      );

      final file = FluppyFile.fromBytes(
        Uint8List.fromList(List.filled(1024, 42)), // 1 KB
        name: 'single-part.bin',
        type: 'application/octet-stream',
      );

      final events = <FluppyEvent>[];
      int progressCallCount = 0;

      final response = await uploader.upload(
        file,
        onProgress: (info) {
          progressCallCount++;
        },
        emitEvent: events.add,
      );

      // Verify upload succeeded
      expect(response.location, equals('$baseUrl/bucket/single-part.bin'));
      expect(progressCallCount, greaterThan(0));
      expect(mockS3.uploadedFiles.containsKey('single-part.bin'), isTrue);
      expect(mockS3.uploadedFiles['single-part.bin']!.length, equals(1024));
    });

    test('tracks progress accurately for single-part upload', () async {
      final uploader = S3Uploader(
        options: S3UploaderOptions(
          shouldUseMultipart: (file) => false,
          getUploadParameters: (file, opts) async {
            return UploadParameters(
              method: 'PUT',
              url: '$baseUrl/bucket/${file.name}',
            );
          },
          createMultipartUpload: (file) => throw UnimplementedError(),
          signPart: (file, opts) => throw UnimplementedError(),
          listParts: (file, opts) => throw UnimplementedError(),
          completeMultipartUpload: (file, opts) => throw UnimplementedError(),
          abortMultipartUpload: (file, opts) async {},
        ),
      );

      const fileSize = 10 * 1024; // 10 KB
      final file = FluppyFile.fromBytes(
        Uint8List.fromList(List.filled(fileSize, 42)),
        name: 'progress.bin',
      );

      final progressUpdates = <UploadProgressInfo>[];

      await uploader.upload(
        file,
        onProgress: (info) {
          progressUpdates.add(info);
        },
        emitEvent: (event) {},
      );

      // Verify progress tracking
      expect(progressUpdates.isNotEmpty, isTrue);
      final lastProgress = progressUpdates.last;
      expect(lastProgress.bytesUploaded, equals(fileSize));
      expect(lastProgress.bytesTotal, equals(fileSize));
      expect(lastProgress.percent, closeTo(100.0, 0.1));
    });
  });

  group('S3 Integration Tests - Multipart Upload', () {
    test('complete multipart upload flow with real HTTP', () async {
      final uploader = S3Uploader(
        options: S3UploaderOptions(
          shouldUseMultipart: (file) => true,
          getChunkSize: (file) => 5 * 1024 * 1024, // 5 MB

          createMultipartUpload: (file) async {
            final uploadId = mockS3.createMultipartUpload(file.name);
            return CreateMultipartUploadResult(
              uploadId: uploadId,
              key: file.name,
            );
          },

          signPart: (file, opts) async {
            return SignPartResult(
              url: '$baseUrl/bucket/${opts.key}'
                  '?uploadId=${opts.uploadId}'
                  '&partNumber=${opts.partNumber}',
            );
          },

          listParts: (file, opts) async {
            final parts = mockS3.listParts(opts.uploadId);
            return parts
                .map((p) => S3Part(
                      partNumber: p['partNumber'] as int,
                      size: p['size'] as int,
                      eTag: p['eTag'] as String,
                    ))
                .toList();
          },

          completeMultipartUpload: (file, opts) async {
            mockS3.completeMultipartUpload(
              opts.uploadId,
              opts.parts
                  .map((p) => {
                        'partNumber': p.partNumber,
                        'eTag': p.eTag,
                      })
                  .toList(),
            );
            return CompleteMultipartResult(
              location: '$baseUrl/bucket/${opts.key}',
            );
          },

          abortMultipartUpload: (file, opts) async {
            mockS3.abortMultipartUpload(opts.uploadId);
          },

          getUploadParameters: (file, opts) => throw UnimplementedError(),
        ),
      );

      // Create 15 MB file (will need 3 parts with 5MB chunks)
      const fileSize = 15 * 1024 * 1024;
      final file = FluppyFile.fromBytes(
        Uint8List.fromList(List.filled(fileSize, 42)),
        name: 'multipart.bin',
      );

      final events = <FluppyEvent>[];
      final response = await uploader.upload(
        file,
        onProgress: (info) {},
        emitEvent: events.add,
      );

      // Verify multipart upload succeeded
      expect(response.location, equals('$baseUrl/bucket/multipart.bin'));

      // Verify 3 parts were uploaded
      final partEvents = events.whereType<PartUploaded>();
      expect(partEvents.length, equals(3));

      // Verify part numbers
      expect(
          partEvents.map((e) => e.part.partNumber).toSet(), equals({1, 2, 3}));
    });

    test('uploads parts concurrently', () async {
      var partUploadCount = 0;

      final uploader = S3Uploader(
        options: S3UploaderOptions(
          shouldUseMultipart: (file) => true,
          getChunkSize: (file) => 5 * 1024 * 1024,
          maxConcurrentParts: 3,
          createMultipartUpload: (file) async {
            final uploadId = mockS3.createMultipartUpload(file.name);
            return CreateMultipartUploadResult(
              uploadId: uploadId,
              key: file.name,
            );
          },
          signPart: (file, opts) async {
            partUploadCount++;
            return SignPartResult(
              url: '$baseUrl/bucket/${opts.key}'
                  '?uploadId=${opts.uploadId}'
                  '&partNumber=${opts.partNumber}',
            );
          },
          listParts: (file, opts) async => [],
          completeMultipartUpload: (file, opts) async {
            mockS3.completeMultipartUpload(
              opts.uploadId,
              opts.parts
                  .map((p) => {
                        'partNumber': p.partNumber,
                        'eTag': p.eTag,
                      })
                  .toList(),
            );
            return CompleteMultipartResult(
              location: '$baseUrl/bucket/${opts.key}',
            );
          },
          abortMultipartUpload: (file, opts) async {},
          getUploadParameters: (file, opts) => throw UnimplementedError(),
        ),
      );

      // Create 20 MB file (4 parts)
      const fileSize = 20 * 1024 * 1024;
      final file = FluppyFile.fromBytes(
        Uint8List.fromList(List.filled(fileSize, 42)),
        name: 'concurrent.bin',
      );

      final response = await uploader.upload(
        file,
        onProgress: (info) {},
        emitEvent: (event) {},
      );

      // Verify upload completed successfully
      expect(response.location, equals('$baseUrl/bucket/concurrent.bin'));
      // Verify all 4 parts were uploaded
      expect(partUploadCount, equals(4));
      expect(mockS3.uploadedFiles.containsKey('concurrent.bin'), isTrue);
    });
  });

  group('S3 Integration Tests - Network Errors', () {
    test('handles network connection error gracefully', () async {
      mockS3.simulateNetworkError = true;

      final uploader = S3Uploader(
        options: S3UploaderOptions(
          shouldUseMultipart: (file) => false,
          retryOptions: const RetryOptions(
            maxRetries: 0, // Disable retry for this test
          ),
          getUploadParameters: (file, opts) async {
            return UploadParameters(
              method: 'PUT',
              url: '$baseUrl/bucket/${file.name}',
            );
          },
          createMultipartUpload: (file) => throw UnimplementedError(),
          signPart: (file, opts) => throw UnimplementedError(),
          listParts: (file, opts) => throw UnimplementedError(),
          completeMultipartUpload: (file, opts) => throw UnimplementedError(),
          abortMultipartUpload: (file, opts) async {},
        ),
      );

      final file = FluppyFile.fromBytes(
        Uint8List.fromList(List.filled(1024, 42)),
        name: 'network-error.bin',
      );

      // Should throw an exception due to network error
      await expectLater(
        uploader.upload(file, onProgress: (info) {}, emitEvent: (event) {}),
        throwsException,
      );
    });

    // Note: Retry logic for network-level errors (socket, connection, timeout) is tested
    // in unit tests. HTTP status code errors (500, etc.) are not retried by default.
    // Integration tests focus on successful upload flows and error detection.
  });

  group('S3 Integration Tests - Expired URLs', () {
    test('detects expired presigned URL (403 response)', () async {
      mockS3.simulateExpiredUrl = true;

      final uploader = S3Uploader(
        options: S3UploaderOptions(
          shouldUseMultipart: (file) => false,
          retryOptions: const RetryOptions(maxRetries: 0),
          getUploadParameters: (file, opts) async {
            return UploadParameters(
              method: 'PUT',
              url: '$baseUrl/bucket/${file.name}',
            );
          },
          createMultipartUpload: (file) => throw UnimplementedError(),
          signPart: (file, opts) => throw UnimplementedError(),
          listParts: (file, opts) => throw UnimplementedError(),
          completeMultipartUpload: (file, opts) => throw UnimplementedError(),
          abortMultipartUpload: (file, opts) async {},
        ),
      );

      final file = FluppyFile.fromBytes(
        Uint8List.fromList(List.filled(1024, 42)),
        name: 'expired.bin',
      );

      // Should throw S3ExpiredUrlException
      await expectLater(
        uploader.upload(file, onProgress: (info) {}, emitEvent: (event) {}),
        throwsA(isA<S3ExpiredUrlException>()),
      );
    });
  });

  group('S3 Integration Tests - Concurrent Uploads', () {
    test('handles multiple file uploads concurrently', () async {
      final uploader = S3Uploader(
        options: S3UploaderOptions(
          shouldUseMultipart: (file) => false,
          getUploadParameters: (file, opts) async {
            return UploadParameters(
              method: 'PUT',
              url: '$baseUrl/bucket/${file.name}',
            );
          },
          createMultipartUpload: (file) => throw UnimplementedError(),
          signPart: (file, opts) => throw UnimplementedError(),
          listParts: (file, opts) => throw UnimplementedError(),
          completeMultipartUpload: (file, opts) => throw UnimplementedError(),
          abortMultipartUpload: (file, opts) async {},
        ),
      );

      // Create 5 small files
      final files = List.generate(
        5,
        (i) => FluppyFile.fromBytes(
          Uint8List.fromList(List.filled(1024, i)),
          name: 'concurrent-$i.bin',
        ),
      );

      // Upload all concurrently
      final futures = files.map((file) => uploader.upload(
            file,
            onProgress: (info) {},
            emitEvent: (event) {},
          ));

      final responses = await Future.wait(futures);

      // Verify all uploads succeeded
      expect(responses.length, equals(5));
      for (var i = 0; i < 5; i++) {
        expect(
          responses[i].location,
          equals('$baseUrl/bucket/concurrent-$i.bin'),
        );
        expect(mockS3.uploadedFiles.containsKey('concurrent-$i.bin'), isTrue);
      }
    });
  });

  group('S3 Integration Tests - Pause/Resume', () {
    test('pauses multipart upload and resumes from where it left off',
        () async {
      var signPartCallCount = 0;

      final uploader = S3Uploader(
        options: S3UploaderOptions(
          shouldUseMultipart: (file) => true,
          getChunkSize: (file) => 5 * 1024 * 1024,
          maxConcurrentParts:
              1, // Upload one part at a time for predictable pause

          createMultipartUpload: (file) async {
            final uploadId = mockS3.createMultipartUpload(file.name);
            return CreateMultipartUploadResult(
              uploadId: uploadId,
              key: file.name,
            );
          },

          signPart: (file, opts) async {
            signPartCallCount++;
            // Add delay to make upload slower, giving time for pause
            await Future.delayed(const Duration(milliseconds: 100));
            return SignPartResult(
              url: '$baseUrl/bucket/${opts.key}'
                  '?uploadId=${opts.uploadId}'
                  '&partNumber=${opts.partNumber}',
            );
          },

          listParts: (file, opts) async {
            final parts = mockS3.listParts(opts.uploadId);
            return parts
                .map((p) => S3Part(
                      partNumber: p['partNumber'] as int,
                      size: p['size'] as int,
                      eTag: p['eTag'] as String,
                    ))
                .toList();
          },

          completeMultipartUpload: (file, opts) async {
            mockS3.completeMultipartUpload(
              opts.uploadId,
              opts.parts
                  .map((p) => {
                        'partNumber': p.partNumber,
                        'eTag': p.eTag,
                      })
                  .toList(),
            );
            return CompleteMultipartResult(
              location: '$baseUrl/bucket/${opts.key}',
            );
          },

          abortMultipartUpload: (file, opts) async {
            mockS3.abortMultipartUpload(opts.uploadId);
          },

          getUploadParameters: (file, opts) => throw UnimplementedError(),
        ),
      );

      // Create 15 MB file (3 parts)
      const fileSize = 15 * 1024 * 1024;
      final file = FluppyFile.fromBytes(
        Uint8List.fromList(List.filled(fileSize, 42)),
        name: 'pause-resume.bin',
      );

      // Start upload in background
      final uploadFuture = uploader.upload(
        file,
        onProgress: (info) {},
        emitEvent: (event) {},
      );

      // Pause after first part starts (give it 50ms to start the first signPart call)
      await Future.delayed(const Duration(milliseconds: 50));
      await uploader.pause(file);

      // Verify at least one part was attempted before pause
      expect(signPartCallCount, greaterThan(0));

      // Reset counter to track resume
      final partsBeforeResume = signPartCallCount;

      // Resume upload - the original uploadFuture will continue
      final resumeFuture = uploader.resume(
        file,
        onProgress: (info) {},
        emitEvent: (event) {},
      );

      // Both futures should complete successfully
      final uploadResponse = await uploadFuture;
      final resumeResponse = await resumeFuture;

      // Verify upload completed
      expect(uploadResponse.location, equals('$baseUrl/bucket/pause-resume.bin'));
      expect(resumeResponse.location, equals('$baseUrl/bucket/pause-resume.bin'));

      // Verify remaining parts were uploaded during resume
      expect(signPartCallCount, greaterThan(partsBeforeResume));
    });
  });
}

/// Mock S3 server for integration testing
class MockS3Server {
  final Map<String, Uint8List> uploadedFiles = {};
  final Map<String, Map<int, Uint8List>> multipartUploads = {};
  final Map<String, String> uploadKeys = {};

  bool simulateNetworkError = false;
  bool simulateExpiredUrl = false;
  void Function()? onBeforeUpload;

  // For retry testing: fail N times before succeeding
  int failureCountBeforeSuccess = 0;
  int _currentAttemptCount = 0;

  Future<shelf.Response> handler(shelf.Request request) async {
    try {
      // Call before upload hook if set
      if (onBeforeUpload != null) {
        onBeforeUpload!();
      }

      // Simulate retry failures
      if (failureCountBeforeSuccess > 0 &&
          _currentAttemptCount < failureCountBeforeSuccess) {
        _currentAttemptCount++;
        return shelf.Response.internalServerError(
          body: 'Simulated transient error',
        );
      }

      // Simulate network error
      if (simulateNetworkError) {
        return shelf.Response.internalServerError(
          body: 'Network error',
        );
      }

      // Simulate expired URL
      if (simulateExpiredUrl) {
        return shelf.Response(
          403,
          body: 'Request has expired',
        );
      }

      final uri = request.url;
      final method = request.method;

      // Single-part upload (PUT request)
      if (method == 'PUT' && !uri.queryParameters.containsKey('uploadId')) {
        return _handleSinglePartUpload(request);
      }

      // Multipart upload part (PUT with uploadId query param)
      if (method == 'PUT' && uri.queryParameters.containsKey('uploadId')) {
        return _handleMultipartPartUpload(request);
      }

      return shelf.Response.notFound('Not found');
    } catch (e) {
      return shelf.Response.internalServerError(
        body: 'Error: $e',
      );
    }
  }

  Future<shelf.Response> _handleSinglePartUpload(shelf.Request request) async {
    final filename = request.url.pathSegments.last;

    // Read request body
    final bodyBytes = await request.read().toList();
    final data = Uint8List.fromList(
      bodyBytes.expand((chunk) => chunk).toList(),
    );
    uploadedFiles[filename] = data;

    return shelf.Response.ok(
      '',
      headers: {
        'etag': '"mock-etag-${DateTime.now().millisecondsSinceEpoch}"',
        'location': request.requestedUri.toString(),
      },
    );
  }

  Future<shelf.Response> _handleMultipartPartUpload(
    shelf.Request request,
  ) async {
    final uploadId = request.url.queryParameters['uploadId']!;
    final partNumber = int.parse(request.url.queryParameters['partNumber']!);

    // Read and store part data
    final bodyBytes = await request.read().toList();
    final data = Uint8List.fromList(
      bodyBytes.expand((chunk) => chunk).toList(),
    );

    multipartUploads.putIfAbsent(uploadId, () => {});
    multipartUploads[uploadId]![partNumber] = data;

    final eTag = '"part-$partNumber-${data.length}"';

    return shelf.Response.ok(
      '',
      headers: {
        'etag': eTag,
      },
    );
  }

  String createMultipartUpload(String filename) {
    final uploadId = 'upload-${DateTime.now().millisecondsSinceEpoch}';
    uploadKeys[uploadId] = filename;
    multipartUploads[uploadId] = {};
    return uploadId;
  }

  List<Map<String, dynamic>> listParts(String uploadId) {
    final parts = multipartUploads[uploadId] ?? {};
    return parts.entries.map((entry) {
      return {
        'partNumber': entry.key,
        'size': entry.value.length,
        'eTag': '"part-${entry.key}-${entry.value.length}"',
      };
    }).toList()
      ..sort(
          (a, b) => (a['partNumber'] as int).compareTo(b['partNumber'] as int));
  }

  void completeMultipartUpload(
    String uploadId,
    List<Map<String, dynamic>> parts,
  ) {
    final filename = uploadKeys[uploadId]!;
    final uploadParts = multipartUploads[uploadId]!;

    // Combine all parts
    final combinedData = <int>[];
    for (var part in parts) {
      final partNumber = part['partNumber'] as int;
      final partData = uploadParts[partNumber]!;
      combinedData.addAll(partData);
    }

    uploadedFiles[filename] = Uint8List.fromList(combinedData);
  }

  void abortMultipartUpload(String uploadId) {
    multipartUploads.remove(uploadId);
    uploadKeys.remove(uploadId);
  }

  void reset() {
    uploadedFiles.clear();
    multipartUploads.clear();
    uploadKeys.clear();
    simulateNetworkError = false;
    simulateExpiredUrl = false;
    onBeforeUpload = null;
    failureCountBeforeSuccess = 0;
    _currentAttemptCount = 0;
  }
}
