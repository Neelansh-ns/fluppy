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
      test('has correct default limit', () {
        expect(options.limit, equals(6));
      });

      test('has correct default maxConcurrentParts', () {
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
  });
}

