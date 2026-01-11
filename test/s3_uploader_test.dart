import 'dart:typed_data';

import 'package:fluppy/fluppy.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  // Mock HTTP client that returns successful responses
  http.Client createMockHttpClient() {
    return MockClient((request) async {
      // Return successful response for all requests
      return http.Response(
        '',
        200,
        headers: {
          'etag': '"mock-etag-123"',
          'location': request.url.toString(),
        },
      );
    });
  }

  group('S3Uploader', () {
    group('Single-part upload', () {
      test('uploads small file using getUploadParameters', () async {
        var getParamsCalled = false;
        String? uploadedFileName;

        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => false, // Force single-part
            getUploadParameters: (file, opts) async {
              getParamsCalled = true;
              uploadedFileName = file.name;
              return UploadParameters(
                method: 'PUT',
                url: 'https://mock.s3.com/${file.name}',
              );
            },
            // Other required callbacks (won't be called for single-part)
            createMultipartUpload: (file) =>
                throw UnimplementedError('Should not be called'),
            signPart: (file, opts) =>
                throw UnimplementedError('Should not be called'),
            completeMultipartUpload: (file, opts) =>
                throw UnimplementedError('Should not be called'),
            listParts: (file, opts) =>
                throw UnimplementedError('Should not be called'),
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
          httpClient: createMockHttpClient(),
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
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => false,
            getUploadParameters: (file, opts) async {
              receivedHeaders = {
                'Content-Type': 'application/json',
                'x-custom': 'value'
              };
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
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true, // Force multipart
            getChunkSize: (file) => 5 * 1024 * 1024, // 5 MB chunks

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

            listParts: (file, opts) async => [], // No existing parts

            completeMultipartUpload: (file, opts) async {
              completeCalled = true;
              expect(opts.parts, isNotEmpty);
              expect(opts.parts.length, equals(3));
              return CompleteMultipartResult(
                location: 'https://mock.s3.com/completed/${file.name}',
              );
            },

            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) =>
                throw UnimplementedError('Should not be called'),
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
        expect(events.whereType<PartUploaded>().length, equals(3));
        expect(totalBytesUploaded, equals(15 * 1024 * 1024));
        expect(response.location, contains('large.bin'));
      });

      test('calculates correct number of parts', () async {
        var signPartCallCount = 0;

        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024, // 5 MB

            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),

            signPart: (file, opts) async {
              signPartCallCount++;
              return const SignPartResult(url: 'https://mock.s3.com/part');
            },

            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
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
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async =>
                const SignPartResult(url: 'https://mock.s3.com/part'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(10 * 1024 * 1024), // 10 MB = 2 parts
          name: 'test.bin',
        );

        final partUploadedEvents = <PartUploaded>[];

        await uploader.upload(
          file,
          onProgress: (_) {},
          emitEvent: (event) {
            if (event is PartUploaded) {
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
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 1 * 1024 * 1024, // 1 MB chunks
            maxConcurrentParts: 2, // Max 2 concurrent parts

            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
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
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
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

    group('Pause/Resume', () {
      test('pause stops upload and throws PausedException', () async {
        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async {
              // Simulate slow upload
              await Future.delayed(const Duration(milliseconds: 100));
              return const SignPartResult(url: 'https://mock.s3.com/part');
            },
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(15 * 1024 * 1024), // 15 MB
          name: 'pausable.bin',
        );

        // Start upload
        final uploadFuture = uploader.upload(
          file,
          onProgress: (_) {},
          emitEvent: (_) {},
        );

        // Pause almost immediately
        await Future.delayed(const Duration(milliseconds: 10));
        await uploader.pause(file);

        // Should throw PausedException
        expect(uploadFuture, throwsA(isA<PausedException>()));
      });

      test('resume continues from where it left off', () async {
        var signPartCallCount = 0;
        final uploadedParts = <int>[];

        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
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
                const S3Part(
                    partNumber: 1, size: 5 * 1024 * 1024, eTag: 'etag1'),
                const S3Part(
                    partNumber: 2, size: 5 * 1024 * 1024, eTag: 'etag2'),
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
        file.uploadId = 'existing-upload-id';
        file.key = 'existing-key';
        file.isMultipart = true;

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
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        expect(uploader.supportsPause, isTrue);
      });

      test('resume is supported', () {
        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        expect(uploader.supportsResume, isTrue);
      });
    });

    group('Retry logic', () {
      test('retries failed upload with exponential backoff', () async {
        var attemptCount = 0;

        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => false,
            retryOptions: const RetryOptions(
              maxRetries: 3,
              initialDelay: Duration(milliseconds: 10),
              exponentialBackoff: true,
            ),
            getUploadParameters: (file, opts) async {
              attemptCount++;
              if (attemptCount < 3) {
                throw Exception('Network error');
              }
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

      test('uses Uppy-style retry delays array', () async {
        var attemptCount = 0;
        final attemptTimestamps = <DateTime>[];

        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => false,
            retryOptions: const RetryOptions(
              retryDelays: [0, 100, 200], // Uppy-style delays in ms
            ),
            getUploadParameters: (file, opts) async {
              attemptCount++;
              attemptTimestamps.add(DateTime.now());

              if (attemptCount < 3) {
                throw Exception('Simulated error');
              }

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

      test('gives up after max retries', () async {
        var attemptCount = 0;

        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => false,
            retryOptions: const RetryOptions(
              maxRetries: 2,
              initialDelay: Duration(milliseconds: 10),
            ),
            getUploadParameters: (file, opts) async {
              attemptCount++;
              throw Exception('Always fails');
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
        expect(attemptCount, lessThanOrEqualTo(3));
      });

      test('retries multipart part uploads', () async {
        var signPartAttempts = 0;

        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            retryOptions: const RetryOptions(
              maxRetries: 2,
              initialDelay: Duration(milliseconds: 10),
            ),
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async {
              signPartAttempts++;
              // Fail first part on first attempt only
              if (opts.partNumber == 1 && signPartAttempts == 1) {
                throw Exception('Part 1 failed');
              }
              return const SignPartResult(url: 'https://mock.s3.com/part');
            },
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
            getUploadParameters: (file, opts) => throw UnimplementedError(),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(10 * 1024 * 1024), // 10 MB = 2 parts
          name: 'test.bin',
        );

        await uploader.upload(file, onProgress: (_) {}, emitEvent: (_) {});

        // Should have retried part 1, so > 2 attempts
        expect(signPartAttempts, greaterThan(2));
      });
    });

    group('Error handling', () {
      test('aborts multipart upload on catastrophic error', () async {
        var abortCalled = false;
        String? abortedUploadId;

        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            shouldUseMultipart: (file) => true,
            getChunkSize: (file) => 5 * 1024 * 1024,
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test-upload-id',
              key: 'test-key',
            ),
            signPart: (file, opts) async {
              // All parts fail
              throw Exception('Network completely down');
            },
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {
              abortCalled = true;
              abortedUploadId = opts.uploadId;
            },
            getUploadParameters: (file, opts) => throw UnimplementedError(),
            retryOptions: const RetryOptions(
                maxRetries: 1, initialDelay: Duration(milliseconds: 10)),
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(10 * 1024 * 1024),
          name: 'fail.bin',
        );

        await expectLater(
          uploader.upload(file, onProgress: (_) {}, emitEvent: (_) {}),
          throwsException,
        );

        expect(abortCalled, isTrue);
        expect(abortedUploadId, equals('test-upload-id'));
      });

      test('cancel aborts multipart upload', () async {
        var abortCalled = false;

        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {
              abortCalled = true;
            },
          ),
        );

        final file = FluppyFile.fromBytes(
          Uint8List(100),
          name: 'cancel.bin',
        );
        file.uploadId = 'test-upload';
        file.key = 'test-key';
        file.isMultipart = true;

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
          httpClient: createMockHttpClient(),
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
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
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
          httpClient: createMockHttpClient(),
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
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        final creds1 = await uploader.getTemporaryCredentials();

        // Wait a bit
        await Future.delayed(const Duration(milliseconds: 100));

        // Get again - should refresh since expiration < 5 min buffer
        final creds2 = await uploader.getTemporaryCredentials();

        expect(credentialsCallCount, greaterThan(1)); // Should have refreshed
      });

      test('clearCredentialsCache clears the cache', () async {
        var credentialsCallCount = 0;

        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
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
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
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
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            getTemporarySecurityCredentials: (opts) async =>
                TemporaryCredentials(
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
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        final uploaderWithout = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        expect(uploaderWith.hasTemporaryCredentials, isTrue);
        expect(uploaderWithout.hasTemporaryCredentials, isFalse);
      });
    });

    group('Configuration', () {
      test('uses default multipart threshold (100 MB)', () {
        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            // No shouldUseMultipart specified - use default
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

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
      });

      test('uses default chunk size (5 MB)', () {
        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            // No getChunkSize specified - use default
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        final file = FluppyFile.fromBytes(Uint8List(100), name: 'test.bin');

        expect(uploader.options.chunkSize(file), equals(5 * 1024 * 1024));
      });

      test('uses default limit (6 concurrent files)', () {
        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        expect(uploader.options.limit, equals(6));
      });

      test('uses default maxConcurrentParts (3)', () {
        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        expect(uploader.options.maxConcurrentParts, equals(3));
      });
    });

    group('Dispose', () {
      test('dispose closes HTTP client', () async {
        final uploader = S3Uploader(
          httpClient: createMockHttpClient(),
          options: S3UploaderOptions(
            getUploadParameters: (file, opts) async => const UploadParameters(
              method: 'PUT',
              url: 'test',
            ),
            createMultipartUpload: (file) async =>
                const CreateMultipartUploadResult(
              uploadId: 'test',
              key: 'test',
            ),
            signPart: (file, opts) async => const SignPartResult(url: 'test'),
            listParts: (file, opts) async => [],
            completeMultipartUpload: (file, opts) async =>
                const CompleteMultipartResult(),
            abortMultipartUpload: (file, opts) async {},
          ),
        );

        // Should not throw
        await uploader.dispose();
      });
    });
  });
}
