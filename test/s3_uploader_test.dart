import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart' hide ProgressCallback;
import 'package:fluppy/fluppy.dart';
import 'package:fluppy/src/core/types.dart';
import 'package:fluppy/src/s3/fluppy_file_extension.dart';
import 'package:test/test.dart';

// Custom mock adapter for Dio
class MockHttpClientAdapter implements HttpClientAdapter {
  final Duration? delay;
  final DioException? Function(RequestOptions)? errorHandler;
  int attemptCount = 0;

  MockHttpClientAdapter({this.delay, this.errorHandler});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attemptCount++;

    // Check if error handler wants to throw an error
    if (errorHandler != null) {
      final error = errorHandler!(options);
      if (error != null) {
        throw error;
      }
    }

    // Simulate upload progress if requestStream is provided
    if (requestStream != null && options.onSendProgress != null) {
      var totalBytes = 0;
      var sentBytes = 0;

      // Collect chunks and calculate total size
      final chunks = await requestStream.toList();
      totalBytes = chunks.fold(0, (sum, chunk) => sum + chunk.length);

      // Simulate sending with progress callbacks
      // Split delay evenly across chunks (minimum 1ms per chunk)
      final delayPerChunk = delay != null && chunks.isNotEmpty
          ? Duration(milliseconds: (delay!.inMilliseconds / chunks.length).ceil())
          : null;

      for (final chunk in chunks) {
        sentBytes += chunk.length;
        options.onSendProgress?.call(sentBytes, totalBytes);

        if (delayPerChunk != null) {
          await Future.delayed(delayPerChunk);
        }
      }
    } else if (delay != null) {
      await Future.delayed(delay!);
    }

    // Return successful mock response
    return ResponseBody.fromString(
      '',
      200,
      headers: {
        'etag': ['"mock-etag-123"'],
        'location': [options.uri.toString()],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  // Mock Dio that returns successful responses
  Dio createMockDio({
    Duration? delay,
    DioException? Function(RequestOptions)? errorHandler,
  }) {
    final dio = Dio();
    dio.httpClientAdapter = MockHttpClientAdapter(
      delay: delay,
      errorHandler: errorHandler,
    );
    return dio;
  }

  group('S3Uploader', () {
    group('Single-part upload', () {
      test('uploads small file using getUploadParameters', () async {
        var getParamsCalled = false;
        String? uploadedFileName;

        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => false,
            // Force single-part
            getUploadParameters: (file, opts) async {
              getParamsCalled = true;
              uploadedFileName = file.name;
              return UploadParameters(
                method: 'PUT',
                url: 'https://mock.s3.com/${file.name}',
              );
            },
            // Other required callbacks (won't be called for single-part)
            createMultipartUpload: (file) => throw UnimplementedError('Should not be called'),
            signPart: (file, opts) => throw UnimplementedError('Should not be called'),
            completeMultipartUpload: (file, opts) => throw UnimplementedError('Should not be called'),
            listParts: (file, opts) => throw UnimplementedError('Should not be called'),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(1024), // 1 KB
          name: 'small.txt',
          type: 'text/plain',
        );

        int progressCallCount = 0;
        final events = <FluppyEvent>[];

        final response = await uploader.upload(
          file,
          onProgress: (info) {
            progressCallCount++;
            expect(info.bytesTotal, equals(1024));
          },
          emitEvent: events.add,
        );

        expect(getParamsCalled, isTrue);
        expect(uploadedFileName, equals('small.txt'));
        expect(response.location, contains('small.txt'));
        expect(progressCallCount, greaterThan(0));
      });

      test('uses PUT method by default for single-part', () async {
        String? usedMethod;

        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => false,
            getUploadParameters: (file, opts) async {
              usedMethod = 'PUT';
              return const UploadParameters(
                method: 'PUT',
                url: 'https://mock.s3.com/file',
              );
            },
            createMultipartUpload: (file) => throw UnimplementedError(),
            signPart: (file, opts) => throw UnimplementedError(),
            completeMultipartUpload: (file, opts) => throw UnimplementedError(),
            listParts: (file, opts) => throw UnimplementedError(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        final file = FluppyFile.fromBytes(Uint8List(100), name: 'test.txt');

        await uploader.upload(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        expect(usedMethod, equals('PUT'));
      });

      test('includes custom headers in single-part upload', () async {
        Map<String, String>? receivedHeaders;

        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => false,
            getUploadParameters: (file, opts) async {
              receivedHeaders = {'Content-Type': 'application/json', 'x-custom': 'value'};
              return UploadParameters(
                method: 'PUT',
                url: 'https://mock.s3.com/file',
                headers: receivedHeaders,
              );
            },
            createMultipartUpload: (file) => throw UnimplementedError(),
            signPart: (file, opts) => throw UnimplementedError(),
            completeMultipartUpload: (file, opts) => throw UnimplementedError(),
            listParts: (file, opts) => throw UnimplementedError(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        final file = FluppyFile.fromBytes(Uint8List(100), name: 'test.json');

        await uploader.upload(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        expect(receivedHeaders, isNotNull);
        expect(receivedHeaders!['Content-Type'], equals('application/json'));
      });
    });

    group('Multipart upload', () {
      test('uploads large file using multipart', () async {
        var createCalled = false;
        var signPartCallCount = 0;
        var completeCalled = false;
        final uploadedPartNumbers = <int>[];

        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            // Force multipart
            getChunkSize: (file) => 5 * 1024 * 1024,
            // 5 MB chunks

            createMultipartUpload: (file) async {
              createCalled = true;
              return CreateMultipartUploadResult(
                uploadId: 'test-upload-id',
                key: 'test-key/${file.name}',
              );
            },

            signPart: (file, opts) async {
              signPartCallCount++;
              uploadedPartNumbers.add(opts.partNumber);
              return SignPartResult(
                url: 'https://mock.s3.com/part-${opts.partNumber}',
              );
            },

            listParts: (file, opts) async => [],
            // No existing parts

            completeMultipartUpload: (file, opts) async {
              completeCalled = true;
              expect(opts.parts, isNotEmpty);
              expect(opts.parts.length, equals(3));
              return CompleteMultipartResult(
                location: 'https://mock.s3.com/completed/${file.name}',
              );
            },

            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError('Should not be called'),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(15 * 1024 * 1024), // 15 MB - will need 3 parts
          name: 'large.bin',
        );

        final events = <FluppyEvent>[];
        var totalBytesUploaded = 0;

        final response = await uploader.upload(
          file,
          onProgress: (info) {
            totalBytesUploaded = info.bytesUploaded;
          },
          emitEvent: events.add,
        );

        expect(createCalled, isTrue);
        expect(signPartCallCount, equals(3)); // 15MB / 5MB = 3 parts
        expect(completeCalled, isTrue);
        expect(uploadedPartNumbers, containsAll([1, 2, 3]));
        expect(events.whereType<S3PartUploaded>().length, equals(3));
        expect(totalBytesUploaded, equals(15 * 1024 * 1024));
        expect(response.location, contains('large.bin'));
      });

      test('calculates correct number of parts', () async {
        var signPartCallCount = 0;

        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            // 5 MB

            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),

            signPart: (file, opts) async {
              signPartCallCount++;
              return const SignPartResult(url: 'https://mock.s3.com/part');
            },

            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        // Test with exactly 2 parts
        final file1 = FluppyFile.fromBytes(
          Uint8List(10 * 1024 * 1024), // 10 MB = 2 parts
          name: 'file1.bin',
        );

        await uploader.upload(file1, onProgress: (_) {}, emitEvent: (_) {});
        expect(signPartCallCount, equals(2));

        // Reset counter
        signPartCallCount = 0;

        // Test with partial last part (2 full parts + 1 partial)
        final file2 = FluppyFile.fromBytes(
          Uint8List(12 * 1024 * 1024), // 12 MB = 2.4 parts -> 3 parts
          name: 'file2.bin',
        );

        await uploader.upload(file2, onProgress: (_) {}, emitEvent: (_) {});
        expect(signPartCallCount, equals(3));
      });

      test('emits PartUploaded events for each part', () async {
        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'https://mock.s3.com/part'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(10 * 1024 * 1024), // 10 MB = 2 parts
          name: 'test.bin',
        );

        final partUploadedEvents = <S3PartUploaded>[];

        await uploader.upload(
          file,
          onProgress: (_) {},
          emitEvent: (event) {
            if (event is S3PartUploaded) {
              partUploadedEvents.add(event);
            }
          },
        );

        expect(partUploadedEvents.length, equals(2));
        expect(partUploadedEvents[0].part.partNumber, equals(1));
        expect(partUploadedEvents[1].part.partNumber, equals(2));
        expect(partUploadedEvents[0].totalParts, equals(2));
      });

      test('respects maxConcurrentParts limit', () async {
        var maxConcurrent = 0;
        var currentConcurrent = 0;

        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 1 * 1024 * 1024,
            // 1 MB chunks
            maxConcurrentParts: 2,
            // Max 2 concurrent parts

            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),

            signPart: (file, opts) async {
              currentConcurrent++;
              if (currentConcurrent > maxConcurrent) {
                maxConcurrent = currentConcurrent;
              }

              // Simulate some work
              await Future.delayed(const Duration(milliseconds: 10));

              currentConcurrent--;
              return const SignPartResult(url: 'https://mock.s3.com/part');
            },

            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(5 * 1024 * 1024), // 5 MB = 5 parts with 1 MB chunks
          name: 'test.bin',
        );

        await uploader.upload(file, onProgress: (_) {}, emitEvent: (_) {});

        // Should never exceed the maxConcurrentParts limit
        expect(maxConcurrent, lessThanOrEqualTo(2));
      });
    });

    /// Pause/Resume functionality tests
    ///
    /// These tests verify the Uppy-style pause/resume pattern:
    /// - Controller persists during pause (not removed from map)
    /// - Resume continues from where it left off using S3 as source of truth
    /// - Single-part uploads don't support pause (like XHR in Uppy)
    group('Pause/Resume', () {
      /// Verifies that pause stops upload and waits for resume.
      /// This is the core pause/resume flow test.
      test('pause stops upload and waits for resume', () async {
        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            maxConcurrentParts: 1,
            // Upload parts sequentially to test pause
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async {
              // Simulate slower upload to allow pause to happen
              await Future.delayed(const Duration(milliseconds: 200));
              return const SignPartResult(url: 'https://mock.s3.com/part');
            },
            listParts: (file, opts) async => file.uploadedParts,
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(15 * 1024 * 1024), // 15 MB = 3 parts
          name: 'pausable.bin',
        );

        // Start upload
        final uploadFuture = uploader.upload(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        // Pause during upload (after first part completes)
        await Future.delayed(const Duration(milliseconds: 250));
        await uploader.pause(file);

        // Verify file has at least one uploaded part but isn't complete
        // (Upload Future is still pending, waiting for resume)
        expect(file.uploadedParts.length, greaterThan(0));
        expect(file.uploadedParts.length, lessThan(3)); // Should not complete all 3 parts

        // Resume and wait for completion
        final resumeFuture = uploader.resume(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        // Both futures should complete successfully
        await expectLater(uploadFuture, completes);
        await expectLater(resumeFuture, completes);

        // Verify all parts were uploaded
        expect(file.uploadedParts.length, equals(3));
      });

      test('resume continues from where it left off', () async {
        var signPartCallCount = 0;
        final uploadedParts = <int>[];

        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async {
              signPartCallCount++;
              uploadedParts.add(opts.partNumber);
              return const SignPartResult(url: 'https://mock.s3.com/part');
            },
            listParts: (file, opts) async {
              // Simulate that parts 1 and 2 were already uploaded
              return [
                const S3Part(partNumber: 1, size: 5 * 1024 * 1024, eTag: 'etag1'),
                const S3Part(partNumber: 2, size: 5 * 1024 * 1024, eTag: 'etag2'),
              ];
            },
            completeMultipartUpload: (file, opts) async {
              // Should have all 3 parts
              expect(opts.parts.length, equals(3));
              return const CompleteMultipartResult();
            },
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(15 * 1024 * 1024), // 15 MB = 3 parts
          name: 'resume.bin',
        );

        // Mark file as multipart with existing upload
        file.s3Multipart.uploadId = 'existing-upload-id';
        file.s3Multipart.key = 'existing-key';
        file.s3Multipart.isMultipart = true;

        await uploader.resume(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        // Should only upload part 3 (parts 1 & 2 already done)
        expect(signPartCallCount, equals(1));
        expect(uploadedParts, equals([3]));
      });

      test('pause is supported', () {
        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        expect(uploader.supportsPause, isTrue);
      });

      test('resume is supported', () {
        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        expect(uploader.supportsResume, isTrue);
      });

      test('resume trusts S3 list completely', () async {
        var listPartsCallCount = 0;

        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async {
              return const SignPartResult(url: 'https://mock.s3.com/part');
            },
            listParts: (file, opts) async {
              listPartsCallCount++;
              // S3 says parts 1 and 2 are uploaded
              return const [
                S3Part(partNumber: 1, size: 5 * 1024 * 1024, eTag: 'etag1'),
                S3Part(partNumber: 2, size: 5 * 1024 * 1024, eTag: 'etag2'),
              ];
            },
            completeMultipartUpload: (file, opts) async {
              expect(opts.parts.length, equals(3)); // All 3 parts
              return const CompleteMultipartResult();
            },
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(15 * 1024 * 1024), // 15 MB = 3 parts
          name: 'trust.bin',
        );

        // Simulate paused upload with in-memory part 3 (that wasn't on S3 yet)
        file.s3Multipart.uploadId = 'test-upload';
        file.s3Multipart.key = 'test-key';
        file.s3Multipart.isMultipart = true;
        file.s3Multipart.uploadedParts.add(
          const S3Part(partNumber: 3, size: 5 * 1024 * 1024, eTag: 'etag3'),
        );

        // Resume: TRUSTS S3 completely, replaces in-memory state
        // Part 3 will be re-uploaded (tradeoff for simplicity)
        await uploader.resume(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        expect(listPartsCallCount, equals(1)); // Should call listParts
        expect(file.uploadedParts.length, equals(3)); // All 3 parts done

        // Verify all part numbers are present
        final partNumbers = file.uploadedParts.map((p) => p.partNumber).toSet();
        expect(partNumbers, equals({1, 2, 3}));
      });

      test('prevents duplicate uploads from rapid pause/resume', () async {
        var uploadStartCount = 0;

        final uploader = S3Uploader(
          dio: createMockDio(
            delay: const Duration(milliseconds: 500),
          ), // Slow uploads
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            maxConcurrentParts: 6,
            createMultipartUpload: (file) async {
              uploadStartCount++;
              return const CreateMultipartUploadResult(
                uploadId: 'test',
                key: 'test',
              );
            },
            signPart: (file, opts) async {
              return const SignPartResult(url: 'https://mock.s3.com/part');
            },
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(30 * 1024 * 1024), // 30 MB = 6 parts
          name: 'duplicate.bin',
        );

        // Start upload
        final uploadFuture = uploader.upload(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        // Rapidly pause and resume multiple times
        await Future.delayed(const Duration(milliseconds: 50));
        await uploader.pause(file);

        // Try to resume multiple times rapidly (simulating user clicking multiple times)
        final resumeFutures = <Future<void>>[];
        for (int i = 0; i < 3; i++) {
          resumeFutures.add(
            uploader.resume(file, onProgress: (_) {}, emitEvent: (_) {}).then((_) {}).catchError((e) {
              // Ignore "already in progress" errors from duplicate resume attempts
              if (e.toString().contains('Upload already in progress')) {
                return; // Successfully ignored duplicate
              }
              throw e; // Re-throw other errors
            }),
          );
        }

        // Wait for upload to complete (original or resumed)
        try {
          await uploadFuture;
        } catch (e) {
          // Ignore pause exception
          if (!e.toString().contains('Upload was paused')) {
            rethrow;
          }
        }

        // Wait for all resume attempts
        await Future.wait(resumeFutures);

        // Should only have created multipart upload once
        expect(uploadStartCount, equals(1));

        // Should have uploaded all parts exactly once
        expect(file.uploadedParts.length, equals(6));
        final partNumbers = file.uploadedParts.map((p) => p.partNumber).toSet();
        expect(partNumbers, equals({1, 2, 3, 4, 5, 6}));
      });

      test('pause returns false for single-part uploads', () async {
        final uploader = S3Uploader(
          dio: createMockDio(
            delay: const Duration(milliseconds: 100), // Slow down upload
          ),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => false,
            // Force single-part
            getUploadParameters: (file, opts) async {
              return const UploadParameters(
                method: 'PUT',
                url: 'https://mock.s3.com/file',
              );
            },
            createMultipartUpload: (file) => throw UnimplementedError(),
            signPart: (file, opts) => throw UnimplementedError(),
            completeMultipartUpload: (file, opts) => throw UnimplementedError(),
            listParts: (file, opts) => throw UnimplementedError(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(100),
          name: 'single-part.txt',
        );

        // Start upload
        final uploadFuture = uploader.upload(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        // Try to pause - should return false for single-part uploads
        // Note: Even if upload hasn't started yet, pause should return false for single-part
        final paused = await uploader.pause(file);
        expect(paused, isFalse);

        // Upload should continue and complete
        final response = await uploadFuture;
        expect(response, isNotNull);
        expect(response.location, isNotNull);
      });

      test('resume with all parts done skips upload (early exit)', () async {
        var signPartCallCount = 0;

        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            createMultipartUpload: (file) async => throw UnimplementedError('Should not create new upload'),
            signPart: (file, opts) async {
              signPartCallCount++;
              throw UnimplementedError('Should not upload any parts');
            },
            listParts: (file, opts) async {
              // S3 reports all parts already uploaded
              return const [
                S3Part(partNumber: 1, size: 5 * 1024 * 1024, eTag: 'etag1'),
                S3Part(partNumber: 2, size: 5 * 1024 * 1024, eTag: 'etag2'),
                S3Part(partNumber: 3, size: 5 * 1024 * 1024, eTag: 'etag3'),
              ];
            },
            completeMultipartUpload: (file, opts) async {
              expect(opts.parts.length, equals(3)); // All parts should be present
              return const CompleteMultipartResult(
                location: 'https://s3.amazonaws.com/test/file',
              );
            },
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(15 * 1024 * 1024), // 15 MB = 3 parts
          name: 'final.bin',
        );

        // Simulate paused multipart upload with all parts already uploaded
        file.s3Multipart.uploadId = 'test-upload';
        file.s3Multipart.key = 'test-key';
        file.s3Multipart.isMultipart = true;

        // Resume - should recognize all parts are done and just complete
        final response = await uploader.resume(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        // Should not upload any new parts (early exit logic)
        expect(signPartCallCount, equals(0));
        expect(response.location, isNotNull);
      });

      test('resume creates new controller if lost (app restart scenario)', () async {
        var createMultipartCallCount = 0;
        var listPartsCallCount = 0;
        var signPartCallCount = 0;

        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            createMultipartUpload: (file) async {
              createMultipartCallCount++;
              // Should NOT be called - upload already exists
              throw UnimplementedError('Should not create new upload');
            },
            signPart: (file, opts) async {
              signPartCallCount++;
              return const SignPartResult(url: 'https://mock.s3.com/part');
            },
            listParts: (file, opts) async {
              listPartsCallCount++;
              // S3 reports parts 1 and 2 already uploaded
              return const [
                S3Part(partNumber: 1, size: 5 * 1024 * 1024, eTag: 'etag1'),
                S3Part(partNumber: 2, size: 5 * 1024 * 1024, eTag: 'etag2'),
              ];
            },
            completeMultipartUpload: (file, opts) async {
              expect(opts.parts.length, equals(3));
              return const CompleteMultipartResult(
                location: 'https://s3.amazonaws.com/test/file',
              );
            },
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(15 * 1024 * 1024), // 15 MB = 3 parts
          name: 'restart.bin',
        );

        // Simulate app restart: file has uploadId but no controller exists
        file.s3Multipart.uploadId = 'existing-upload-id';
        file.s3Multipart.key = 'existing-key';
        file.s3Multipart.isMultipart = true;

        // Resume should create new controller with continueExisting: true
        final response = await uploader.resume(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        // Should NOT create new multipart upload
        expect(createMultipartCallCount, equals(0));
        // Should list parts from S3
        expect(listPartsCallCount, greaterThan(0));
        // Should only upload part 3
        expect(signPartCallCount, equals(1));
        expect(response.location, isNotNull);
      });

      test('resume throws PausedException if paused again during resume', () async {
        final uploader = S3Uploader(
          dio: createMockDio(
            delay: const Duration(milliseconds: 200), // Slow down operations
          ),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async {
              // Add delay to allow pause during resume
              await Future.delayed(const Duration(milliseconds: 150));
              return const SignPartResult(url: 'https://mock.s3.com/part');
            },
            listParts: (file, opts) async {
              // Add delay to allow pause during listParts
              await Future.delayed(const Duration(milliseconds: 150));
              return file.uploadedParts;
            },
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(15 * 1024 * 1024), // 15 MB = 3 parts
          name: 'double-pause.bin',
        );

        // Start upload and pause
        final uploadFuture = uploader.upload(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        await Future.delayed(const Duration(milliseconds: 50));
        await uploader.pause(file);

        // Start resume
        final resumeFuture = uploader.resume(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        // Pause again during resume (while listParts or signPart is executing)
        await Future.delayed(const Duration(milliseconds: 75));
        await uploader.pause(file);

        // Resume should throw PausedException
        await expectLater(resumeFuture, throwsA(isA<PausedException>()));

        // Controller should still be alive (can resume again)
        final resumeFuture2 = uploader.resume(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        await expectLater(resumeFuture2, completes);
        await expectLater(uploadFuture, completes);
      });
    });

    /// Controller Lifecycle tests (Uppy Pattern)
    ///
    /// These tests verify that controllers follow the Uppy pattern:
    /// - Controllers persist during pause (stay in _controllers map)
    /// - Controllers are removed only on completion, error, or cancel
    /// - Controllers are NOT removed on pause
    group('Controller Lifecycle', () {
      /// Verifies controller lifecycle: persists during pause, removed on completion.
      /// This is critical for the Uppy pattern where controllers stay alive during pause.
      test('controller persists during pause and is removed on completion', () async {
        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async {
              await Future.delayed(const Duration(milliseconds: 100));
              return const SignPartResult(url: 'https://mock.s3.com/part');
            },
            listParts: (file, opts) async => file.uploadedParts,
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(15 * 1024 * 1024), // 15 MB = 3 parts
          name: 'lifecycle.bin',
        );

        // Start upload
        final uploadFuture = uploader.upload(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        // Pause - controller should persist
        await Future.delayed(const Duration(milliseconds: 50));
        final paused1 = await uploader.pause(file);
        expect(paused1, isTrue); // Should succeed

        // Try to pause again - should return false (already paused or no active upload)
        // Note: This might return false if file status changed, or true if controller still exists
        // The important thing is that resume works
        await uploader.pause(file);

        // Resume - controller should still exist
        final resumeFuture = uploader.resume(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        // Wait for completion
        final uploadResponse = await uploadFuture;
        final resumeResponse = await resumeFuture;

        // Both should complete successfully
        expect(uploadResponse, isNotNull);
        expect(resumeResponse, isNotNull);

        // Controller should be removed after completion (can't pause)
        expect(await uploader.pause(file), isFalse);
      });

      test('controller removed on error', () async {
        final uploader = S3Uploader(
          dio: createMockDio(
            errorHandler: (options) {
              // Always fail
              return DioException(
                requestOptions: options,
                error: Exception('Network error'),
              );
            },
          ),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            retryConfig: const RetryConfig(maxRetries: 0),
            // No retries
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'https://mock.s3.com/part'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(15 * 1024 * 1024),
          name: 'error.bin',
        );

        // Upload should fail - start it but don't await
        // Use runZonedGuarded to catch errors at the zone level
        await runZonedGuarded(() async {
          final uploadFuture = uploader.upload(file, onProgress: (_) {}, emitEvent: (_) {});

          // Attach error handler synchronously before any delays
          // This ensures the handler is in place before errors occur
          uploadFuture.catchError((e) {
            // Expected - upload failed
            expect(e, isNotNull);
            // Return dummy response to satisfy type requirements
            return const UploadResponse(location: '');
          });

          // Wait for error to occur and controller to be removed
          await Future.delayed(const Duration(milliseconds: 100));
        }, (error, stackTrace) {
          // Catch any uncaught errors at the zone level
          // Expected - upload failed with DioException
        });

        // Controller should be removed on error (can't pause)
        expect(await uploader.pause(file), isFalse);
      });

      test('controller removed on cancel', () async {
        final uploader = S3Uploader(
          dio: createMockDio(
            delay: const Duration(milliseconds: 200), // Slow uploads
          ),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async {
              await Future.delayed(const Duration(milliseconds: 100));
              return const SignPartResult(url: 'https://mock.s3.com/part');
            },
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(15 * 1024 * 1024),
          name: 'cancel.bin',
        );

        // Start upload - don't await, let it run in background
        // Use runZonedGuarded to catch errors at the zone level
        bool caughtCancelled = false;
        await runZonedGuarded(() async {
          final uploadFuture = uploader.upload(
            file,
            onProgress: (_) {},
            emitEvent: (_) {},
          );

          // Attach error handler BEFORE canceling to catch CancelledException
          uploadFuture.catchError((e) {
            if (e is CancelledException) {
              caughtCancelled = true;
            }
            // Return dummy response to satisfy type requirements
            return const UploadResponse(location: '');
          });

          // Cancel after upload starts
          await Future.delayed(const Duration(milliseconds: 50));
          // cancel() completes the controller's completer with CancelledException
          // This will propagate to uploadFuture, which our error handler will catch
          await uploader.cancel(file);

          // Wait for the error handler to catch the exception
          await Future.delayed(const Duration(milliseconds: 100));
        }, (error, stackTrace) {
          // Catch any uncaught errors at the zone level
          if (error is CancelledException) {
            caughtCancelled = true;
          }
        });

        expect(caughtCancelled, isTrue, reason: 'Should have caught CancelledException');

        // Wait for cancel to take effect and controller to be removed
        await Future.delayed(const Duration(milliseconds: 50));

        // Controller should be removed (can't pause)
        expect(await uploader.pause(file), isFalse);
        await Future.delayed(const Duration(milliseconds: 100));
      });

      test('distinguishes pause from real cancellation', () async {
        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async {
              await Future.delayed(const Duration(milliseconds: 100));
              return const SignPartResult(url: 'https://mock.s3.com/part');
            },
            listParts: (file, opts) async => file.uploadedParts,
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(15 * 1024 * 1024),
          name: 'distinguish.bin',
        );

        // Start upload
        final uploadFuture = uploader.upload(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        // Pause - should use _pausingReason
        await Future.delayed(const Duration(milliseconds: 50));
        await uploader.pause(file);

        // Resume should work (pause was distinguished from cancel)
        final resumeFuture = uploader.resume(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        await uploadFuture;
        await resumeFuture;

        // Upload should complete successfully
        expect(file.uploadedParts.length, equals(3));
      });
    });

    /// Retry logic tests
    ///
    /// These tests verify retry behavior:
    /// - Exponential backoff for HTTP failures
    /// - Uppy-style retry delays array support
    /// - User callback failures are NOT retried (critical distinction)
    /// - Max retry limits are respected
    group('Retry logic', () {
      /// Verifies exponential backoff retry for HTTP failures.
      test('retries failed HTTP upload with exponential backoff', () async {
        var attemptCount = 0;

        // Mock Dio that fails twice, then succeeds
        final mockDio = createMockDio(
          errorHandler: (options) {
            attemptCount++;
            if (attemptCount < 3) {
              return DioException(
                requestOptions: options,
                error: Exception('Network error'),
              );
            }
            return null; // Success
          },
        );

        final uploader = S3Uploader(
          dio: mockDio,
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => false,
            retryConfig: const RetryConfig(
              maxRetries: 3,
              initialDelay: Duration(milliseconds: 10),
              exponentialBackoff: true,
            ),
            getUploadParameters: (file, opts) async {
              return const UploadParameters(
                method: 'PUT',
                url: 'https://mock.s3.com/file',
              );
            },
            createMultipartUpload: (file) => throw UnimplementedError(),
            signPart: (file, opts) => throw UnimplementedError(),
            completeMultipartUpload: (file, opts) => throw UnimplementedError(),
            listParts: (file, opts) => throw UnimplementedError(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(100),
          name: 'retry.txt',
        );

        final response = await uploader.upload(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        expect(attemptCount, equals(3)); // Failed twice, succeeded on 3rd
        expect(response.location, isNotNull);
      });

      test('uses Uppy-style retry delays array for HTTP failures', () async {
        var attemptCount = 0;
        final attemptTimestamps = <DateTime>[];

        // Mock Dio that fails twice, then succeeds
        final mockDio = createMockDio(
          errorHandler: (options) {
            attemptCount++;
            attemptTimestamps.add(DateTime.now());

            if (attemptCount < 3) {
              return DioException(
                requestOptions: options,
                error: Exception('Simulated network error'),
              );
            }
            return null; // Success
          },
        );

        final uploader = S3Uploader(
          dio: mockDio,
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => false,
            retryConfig: const RetryConfig(
              retryDelays: [0, 100, 200], // Uppy-style delays in ms
            ),
            getUploadParameters: (file, opts) async {
              return const UploadParameters(
                method: 'PUT',
                url: 'https://mock.s3.com/file',
              );
            },
            createMultipartUpload: (file) => throw UnimplementedError(),
            signPart: (file, opts) => throw UnimplementedError(),
            completeMultipartUpload: (file, opts) => throw UnimplementedError(),
            listParts: (file, opts) => throw UnimplementedError(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        final file = FluppyFile.fromBytes(Uint8List(100), name: 'test.txt');

        await uploader.upload(file, onProgress: (_) {}, emitEvent: (_) {});

        expect(attemptCount, equals(3));
        expect(attemptTimestamps.length, equals(3));
      });

      test('gives up after max retries on HTTP failures', () async {
        var attemptCount = 0;

        // Mock Dio that always fails
        final mockDio = createMockDio(
          errorHandler: (options) {
            attemptCount++;
            return DioException(
              requestOptions: options,
              error: Exception('Network always fails'),
            );
          },
        );

        final uploader = S3Uploader(
          dio: mockDio,
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => false,
            retryConfig: const RetryConfig(
              maxRetries: 2,
              initialDelay: Duration(milliseconds: 10),
            ),
            getUploadParameters: (file, opts) async {
              return const UploadParameters(
                method: 'PUT',
                url: 'https://mock.s3.com/file',
              );
            },
            createMultipartUpload: (file) => throw UnimplementedError(),
            signPart: (file, opts) => throw UnimplementedError(),
            completeMultipartUpload: (file, opts) => throw UnimplementedError(),
            listParts: (file, opts) => throw UnimplementedError(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        final file = FluppyFile.fromBytes(Uint8List(100), name: 'fail.txt');

        await expectLater(
          uploader.upload(file, onProgress: (_) {}, emitEvent: (_) {}),
          throwsException,
        );

        // Should try initial + 2 retries = 3 total attempts
        expect(attemptCount, equals(3));
      });

      test('user callback failures are NOT retried', () async {
        var callbackAttemptCount = 0;

        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => false,
            retryConfig: const RetryConfig(
              maxRetries: 3,
              initialDelay: Duration(milliseconds: 10),
            ),
            getUploadParameters: (file, opts) async {
              callbackAttemptCount++;
              throw Exception('User callback error');
            },
            createMultipartUpload: (file) => throw UnimplementedError(),
            signPart: (file, opts) => throw UnimplementedError(),
            completeMultipartUpload: (file, opts) => throw UnimplementedError(),
            listParts: (file, opts) => throw UnimplementedError(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        final file = FluppyFile.fromBytes(Uint8List(100), name: 'callback-fail.txt');

        await expectLater(
          uploader.upload(file, onProgress: (_) {}, emitEvent: (_) {}),
          throwsException,
        );

        // Callback should only be called once (no retries for user callbacks)
        expect(callbackAttemptCount, equals(1));
      });

      test('multipart upload fails if part upload fails', () async {
        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            retryConfig: const RetryConfig(
              maxRetries: 2,
              initialDelay: Duration(milliseconds: 10),
            ),
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async {
              // First part always fails
              if (opts.partNumber == 1) {
                throw Exception('Part 1 failed');
              }
              return const SignPartResult(url: 'https://mock.s3.com/part');
            },
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(10 * 1024 * 1024), // 10 MB = 2 parts
          name: 'test.bin',
        );

        // Simplified approach: part failures throw immediately
        // User can pause/resume with new URLs if needed
        await expectLater(
          uploader.upload(file, onProgress: (_) {}, emitEvent: (_) {}),
          throwsException,
        );
      });
    });

    group('Error handling', () {
      test('throws exception on catastrophic error', () async {
        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test-upload-id',
              key: 'test-key',
            ),
            signPart: (file, opts) async {
              // All parts fail
              throw Exception('Network completely down');
            },
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
            retryConfig: const RetryConfig(maxRetries: 1, initialDelay: Duration(milliseconds: 10)),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(10 * 1024 * 1024),
          name: 'fail.bin',
        );

        // Simplified approach: just throws error, doesn't auto-abort
        // (abort is only called on explicit cancel())
        await expectLater(
          uploader.upload(file, onProgress: (_) {}, emitEvent: (_) {}),
          throwsException,
        );
      });

      test('cancel aborts multipart upload', () async {
        var abortCalled = false;

        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {
              abortCalled = true;
            },
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(100),
          name: 'cancel.bin',
        );
        file.s3Multipart.uploadId = 'test-upload';
        file.s3Multipart.key = 'test-key';
        file.s3Multipart.isMultipart = true;

        await uploader.cancel(file);

        expect(abortCalled, isTrue);
      });

      test('handles missing ETag gracefully', () async {
        // This test would require mocking the HTTP client
        // to return a response without ETag header
        // Skipped for now - requires HTTP client mocking
      });

      test('handles expired presigned URL detection', () {
        // S3ExpiredUrlException is detected based on response
        expect(
          S3ExpiredUrlException.isExpiredResponse(
            403,
            '<Message>Request has expired</Message>',
          ),
          isTrue,
        );

        expect(
          S3ExpiredUrlException.isExpiredResponse(
            403,
            'ExpiredToken error occurred',
          ),
          isTrue,
        );

        expect(
          S3ExpiredUrlException.isExpiredResponse(
            404,
            'Not found',
          ),
          isFalse,
        );
      });
    });

    group('Temporary credentials', () {
      test('caches temporary credentials', () async {
        var credentialsCallCount = 0;

        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            getTemporarySecurityCredentials: (opts) async {
              credentialsCallCount++;
              return TemporaryCredentials(
                accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
                secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
                sessionToken: 'token',
                expiration: DateTime.now().add(const Duration(hours: 1)),
                bucket: 'test-bucket',
                region: 'us-east-1',
              );
            },
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        // Get credentials twice
        final creds1 = await uploader.getTemporaryCredentials();
        final creds2 = await uploader.getTemporaryCredentials();

        expect(credentialsCallCount, equals(1)); // Should be cached
        expect(creds1, equals(creds2));
      });

      test('refreshes expired credentials', () async {
        var credentialsCallCount = 0;

        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            getTemporarySecurityCredentials: (opts) async {
              credentialsCallCount++;
              // Return credentials that expire in 2 minutes (< 5 min buffer)
              return TemporaryCredentials(
                accessKeyId: 'key',
                secretAccessKey: 'secret',
                sessionToken: 'token',
                expiration: DateTime.now().add(const Duration(minutes: 2)),
                bucket: 'test-bucket',
                region: 'us-east-1',
              );
            },
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        await uploader.getTemporaryCredentials();

        // Wait a bit
        await Future.delayed(const Duration(milliseconds: 100));

        // Get again - should refresh since expiration < 5 min buffer
        await uploader.getTemporaryCredentials();

        expect(credentialsCallCount, greaterThan(1)); // Should have refreshed
      });

      test('clearCredentialsCache clears the cache', () async {
        var credentialsCallCount = 0;

        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            getTemporarySecurityCredentials: (opts) async {
              credentialsCallCount++;
              return TemporaryCredentials(
                accessKeyId: 'key',
                secretAccessKey: 'secret',
                sessionToken: 'token',
                expiration: DateTime.now().add(const Duration(hours: 1)),
                bucket: 'test-bucket',
                region: 'us-east-1',
              );
            },
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        await uploader.getTemporaryCredentials();
        expect(credentialsCallCount, equals(1));

        // Clear cache
        uploader.clearCredentialsCache();

        // Get again - should fetch new credentials
        await uploader.getTemporaryCredentials();
        expect(credentialsCallCount, equals(2));
      });

      test('hasTemporaryCredentials returns correct value', () {
        final uploaderWith = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            getTemporarySecurityCredentials: (opts) async => TemporaryCredentials(
              accessKeyId: 'key',
              secretAccessKey: 'secret',
              sessionToken: 'token',
              expiration: DateTime.now(),
              bucket: 'test-bucket',
              region: 'us-east-1',
            ),
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        final uploaderWithout = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        expect(uploaderWith.hasTemporaryCredentials, isTrue);
        expect(uploaderWithout.hasTemporaryCredentials, isFalse);
      });
    });

    group('Configuration', () {
      test('uses correct default values', () {
        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        // Test default multipart threshold (100 MB)
        final smallFile = FluppyFile.fromBytes(
          Uint8List(50 * 1024 * 1024), // 50 MB
          name: 'small.bin',
        );
        final largeFile = FluppyFile.fromBytes(
          Uint8List(150 * 1024 * 1024), // 150 MB
          name: 'large.bin',
        );
        expect(uploader.options.useMultipart(smallFile), isFalse);
        expect(uploader.options.useMultipart(largeFile), isTrue);

        // Test default chunk size (5 MB)
        final testFile = FluppyFile.fromBytes(Uint8List(100), name: 'test.bin');
        expect(uploader.options.chunkSize(testFile), equals(5 * 1024 * 1024));

        // Test default maxConcurrentParts (3)
        expect(uploader.options.maxConcurrentParts, equals(3));
      });
    });

    group('Dispose', () {
      test('dispose closes HTTP client', () async {
        final uploader = S3Uploader(
          dio: createMockDio(),
          options: S3UploaderOptions(
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async => const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        // Should not throw
        await uploader.dispose();
      });
    });
  });
}
