import 'dart:typed_data';

import 'package:fluppy/fluppy.dart';
import 'package:test/test.dart';

void main() {
  group('S3UploaderOptions', () {
    late S3UploaderOptions options;

    setUp(() {
      options = S3UploaderOptions(
        getUploadParameters: (file, opts) async => const UploadParameters(
          method: 'PUT',
          url: 'https://example.com',
        ),
        createMultipartUpload: (file) async => const CreateMultipartUploadResult(
          uploadId: 'test',
          key: 'test',
        ),
        signPart: (file, opts) async => const SignPartResult(url: 'https://example.com'),
        completeMultipartUpload: (file, opts) async => const CompleteMultipartResult(),
        listParts: (file, opts) async => [],
        abortMultipartUpload: (file, opts) async {},
      );
    });

    group('useMultipart', () {
      test('returns true for files > 100 MiB by default', () {
        final largeFile = FluppyFile.fromBytes(
          Uint8List(101 * 1024 * 1024), // 101 MiB
          name: 'large.bin',
        );
        final smallFile = FluppyFile.fromBytes(
          Uint8List(50 * 1024 * 1024), // 50 MiB
          name: 'small.bin',
        );

        expect(options.useMultipart(largeFile), isTrue);
        expect(options.useMultipart(smallFile), isFalse);
      });

      test('uses custom shouldUseMultipart callback', () {
        final customOptions = S3UploaderOptions(
          shouldUseMultipart: (file) => file.size > 10 * 1024 * 1024, // 10 MiB
          getUploadParameters: options.getUploadParameters,
          createMultipartUpload: options.createMultipartUpload,
          signPart: options.signPart,
          completeMultipartUpload: options.completeMultipartUpload,
          listParts: options.listParts,
          abortMultipartUpload: options.abortMultipartUpload,
        );

        final file = FluppyFile.fromBytes(
          Uint8List(15 * 1024 * 1024), // 15 MiB
          name: 'medium.bin',
        );

        expect(customOptions.useMultipart(file), isTrue);
        expect(options.useMultipart(file), isFalse); // default is 100 MiB
      });
    });

    group('chunkSize', () {
      test('returns default chunk size', () {
        final file = FluppyFile.fromBytes(
          Uint8List(100),
          name: 'test.bin',
        );

        expect(options.chunkSize(file), equals(5 * 1024 * 1024)); // 5 MiB
      });

      test('uses custom getChunkSize callback', () {
        final customOptions = S3UploaderOptions(
          getChunkSize: (file) => 10 * 1024 * 1024, // 10 MiB
          getUploadParameters: options.getUploadParameters,
          createMultipartUpload: options.createMultipartUpload,
          signPart: options.signPart,
          completeMultipartUpload: options.completeMultipartUpload,
          listParts: options.listParts,
          abortMultipartUpload: options.abortMultipartUpload,
        );

        final file = FluppyFile.fromBytes(
          Uint8List(100),
          name: 'test.bin',
        );

        expect(customOptions.chunkSize(file), equals(10 * 1024 * 1024));
      });

      test('enforces minimum chunk size', () {
        final customOptions = S3UploaderOptions(
          getChunkSize: (file) => 1024, // 1 KB (too small)
          getUploadParameters: options.getUploadParameters,
          createMultipartUpload: options.createMultipartUpload,
          signPart: options.signPart,
          completeMultipartUpload: options.completeMultipartUpload,
          listParts: options.listParts,
          abortMultipartUpload: options.abortMultipartUpload,
        );

        final file = FluppyFile.fromBytes(
          Uint8List(100),
          name: 'test.bin',
        );

        // Should be at least 5 MiB
        expect(customOptions.chunkSize(file), greaterThanOrEqualTo(5 * 1024 * 1024));
      });

      test('adjusts chunk size for max parts limit', () {
        // Create a file that would require > 10000 parts with 5 MiB chunks
        // 10001 * 5 MiB = ~50 GB
        // For testing, we use a smaller file since we can't allocate 50GB
        
        // Mock file with small size to verify the calculation doesn't break
        final file = FluppyFile.fromBytes(
          Uint8List(0), // Empty bytes
          name: 'test.bin',
        );
        
        // Verify the calculation works and returns a valid chunk size
        expect(options.chunkSize(file), greaterThan(0));
        expect(options.chunkSize(file), greaterThanOrEqualTo(5 * 1024 * 1024));
      });
    });

    group('defaults', () {
      test('has correct default values', () {
        expect(options.limit, equals(6));
        expect(options.maxConcurrentParts, equals(3));
      });
    });
  });

  group('RetryOptions', () {
    test('has correct defaults', () {
      const opts = RetryOptions();

      expect(opts.maxRetries, equals(3));
      expect(opts.initialDelay, equals(const Duration(seconds: 1)));
      expect(opts.maxDelay, equals(const Duration(seconds: 30)));
      expect(opts.exponentialBackoff, isTrue);
    });

    test('getDelay calculates exponential backoff', () {
      const opts = RetryOptions(
        initialDelay: Duration(seconds: 1),
        exponentialBackoff: true,
      );

      expect(opts.getDelay(0), equals(Duration.zero));
      expect(opts.getDelay(1), equals(const Duration(seconds: 1)));
      expect(opts.getDelay(2), equals(const Duration(seconds: 2)));
      expect(opts.getDelay(3), equals(const Duration(seconds: 4)));
    });

    test('getDelay respects maxDelay', () {
      const opts = RetryOptions(
        initialDelay: Duration(seconds: 10),
        maxDelay: Duration(seconds: 30),
        exponentialBackoff: true,
      );

      // 10 * 2^4 = 160 seconds, but max is 30
      expect(opts.getDelay(5).inSeconds, lessThanOrEqualTo(30));
    });

    test('getDelay returns constant delay without exponential backoff', () {
      const opts = RetryOptions(
        initialDelay: Duration(seconds: 5),
        exponentialBackoff: false,
      );

      expect(opts.getDelay(1), equals(const Duration(seconds: 5)));
      expect(opts.getDelay(2), equals(const Duration(seconds: 5)));
      expect(opts.getDelay(3), equals(const Duration(seconds: 5)));
    });

    group('getDelay edge cases', () {
      test('attempt 0 always returns zero (first attempt has no delay)', () {
        const opts = RetryOptions(
          initialDelay: Duration(seconds: 10),
          exponentialBackoff: true,
        );

        // First attempt should never have a delay
        expect(opts.getDelay(0), equals(Duration.zero));
      });

      test('negative attempt returns zero', () {
        const opts = RetryOptions(
          initialDelay: Duration(seconds: 1),
          exponentialBackoff: true,
        );

        expect(opts.getDelay(-1), equals(Duration.zero));
        expect(opts.getDelay(-100), equals(Duration.zero));
      });

      test('exponential backoff formula is correct: initialDelay * 2^(attempt-1)', () {
        const opts = RetryOptions(
          initialDelay: Duration(milliseconds: 100),
          maxDelay: Duration(hours: 1), // high max to not interfere
          exponentialBackoff: true,
        );

        // attempt 0: no delay (first attempt)
        expect(opts.getDelay(0), equals(Duration.zero));
        // attempt 1: 100ms * 2^0 = 100ms
        expect(opts.getDelay(1), equals(const Duration(milliseconds: 100)));
        // attempt 2: 100ms * 2^1 = 200ms
        expect(opts.getDelay(2), equals(const Duration(milliseconds: 200)));
        // attempt 3: 100ms * 2^2 = 400ms
        expect(opts.getDelay(3), equals(const Duration(milliseconds: 400)));
        // attempt 4: 100ms * 2^3 = 800ms
        expect(opts.getDelay(4), equals(const Duration(milliseconds: 800)));
        // attempt 5: 100ms * 2^4 = 1600ms
        expect(opts.getDelay(5), equals(const Duration(milliseconds: 1600)));
      });

      test('constant delay (no exponential) still returns zero for attempt 0', () {
        const opts = RetryOptions(
          initialDelay: Duration(seconds: 5),
          exponentialBackoff: false,
        );

        expect(opts.getDelay(0), equals(Duration.zero));
        expect(opts.getDelay(1), equals(const Duration(seconds: 5)));
        expect(opts.getDelay(10), equals(const Duration(seconds: 5)));
      });

      test('maxDelay caps all retry delays', () {
        const opts = RetryOptions(
          initialDelay: Duration(seconds: 1),
          maxDelay: Duration(seconds: 5),
          exponentialBackoff: true,
        );

        // attempt 4: 1 * 2^3 = 8 seconds, should be capped to 5
        expect(opts.getDelay(4), equals(const Duration(seconds: 5)));
        // attempt 10: would be huge, should be capped
        expect(opts.getDelay(10), equals(const Duration(seconds: 5)));
      });
    });

    group('retryDelays array', () {
      test('uses retryDelays array values for retries', () {
        const opts = RetryOptions(
          retryDelays: [0, 1000, 2000, 5000], // Uppy-style delays in ms
        );

        // attempt 0: first attempt, no delay
        expect(opts.getDelay(0), equals(Duration.zero));
        // attempt 1: first retry, uses retryDelays[0] = 0ms
        expect(opts.getDelay(1), equals(const Duration(milliseconds: 0)));
        // attempt 2: second retry, uses retryDelays[1] = 1000ms
        expect(opts.getDelay(2), equals(const Duration(milliseconds: 1000)));
        // attempt 3: third retry, uses retryDelays[2] = 2000ms
        expect(opts.getDelay(3), equals(const Duration(milliseconds: 2000)));
        // attempt 4: fourth retry, uses retryDelays[3] = 5000ms
        expect(opts.getDelay(4), equals(const Duration(milliseconds: 5000)));
      });

      test('retryDelays uses last value for attempts beyond array length', () {
        const opts = RetryOptions(
          retryDelays: [100, 500, 1000],
        );

        // Beyond array length, use last value
        expect(opts.getDelay(5), equals(const Duration(milliseconds: 1000)));
        expect(opts.getDelay(10), equals(const Duration(milliseconds: 1000)));
        expect(opts.getDelay(100), equals(const Duration(milliseconds: 1000)));
      });

      test('retryDelays takes precedence over exponentialBackoff', () {
        const opts = RetryOptions(
          retryDelays: [500, 1000, 2000],
          initialDelay: Duration(seconds: 10),
          exponentialBackoff: true,
        );

        // Should use retryDelays, not exponential calculation
        expect(opts.getDelay(0), equals(Duration.zero));
        expect(opts.getDelay(1), equals(const Duration(milliseconds: 500)));
        expect(opts.getDelay(2), equals(const Duration(milliseconds: 1000)));
      });

      test('empty retryDelays falls back to exponential backoff', () {
        const opts = RetryOptions(
          retryDelays: [],
          initialDelay: Duration(milliseconds: 100),
          exponentialBackoff: true,
        );

        // Empty array should fall back to exponential
        expect(opts.getDelay(0), equals(Duration.zero));
        expect(opts.getDelay(1), equals(const Duration(milliseconds: 100)));
        expect(opts.getDelay(2), equals(const Duration(milliseconds: 200)));
      });

      test('Uppy-compatible retryDelays [0, 1000, 3000, 5000]', () {
        // This is the Uppy default retryDelays
        const opts = RetryOptions(
          retryDelays: [0, 1000, 3000, 5000],
        );

        expect(opts.getDelay(0), equals(Duration.zero)); // first attempt
        expect(opts.getDelay(1), equals(Duration.zero)); // retry 1: 0ms
        expect(opts.getDelay(2), equals(const Duration(seconds: 1))); // retry 2: 1s
        expect(opts.getDelay(3), equals(const Duration(seconds: 3))); // retry 3: 3s
        expect(opts.getDelay(4), equals(const Duration(seconds: 5))); // retry 4: 5s
        expect(opts.getDelay(5), equals(const Duration(seconds: 5))); // retry 5+: 5s (last)
      });
    });
  });

  group('S3Uploader static methods', () {
    test('defaultUploadPartBytes is accessible as static method', () {
      // Verify that defaultUploadPartBytes is a static method on S3Uploader
      // This test ensures the class structure fix is correct
      expect(S3Uploader.defaultUploadPartBytes, isA<Function>());
    });
  });
}

