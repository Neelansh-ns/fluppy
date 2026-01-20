import 'package:fluppy/fluppy.dart';
import 'package:test/test.dart';

void main() {
  group('S3Utils', () {
    group('constructUrl', () {
      test('constructs basic URL', () {
        final url = S3Utils.constructUrl(
          bucket: 'my-bucket',
          region: 'us-east-1',
          key: 'file.jpg',
        );
        expect(url, 'https://my-bucket.s3.us-east-1.amazonaws.com/file.jpg');
      });

      test('encodes spaces in key', () {
        final url = S3Utils.constructUrl(
          bucket: 'my-bucket',
          region: 'us-east-1',
          key: 'my file.jpg',
        );
        expect(url, 'https://my-bucket.s3.us-east-1.amazonaws.com/my%20file.jpg');
      });

      test('encodes special characters', () {
        final url = S3Utils.constructUrl(
          bucket: 'my-bucket',
          region: 'us-east-1',
          key: 'file (1).jpg',
        );
        expect(url, 'https://my-bucket.s3.us-east-1.amazonaws.com/file%20%281%29.jpg');
      });

      test('handles nested paths', () {
        final url = S3Utils.constructUrl(
          bucket: 'my-bucket',
          region: 'us-east-1',
          key: 'uploads/2026/01/file.jpg',
        );
        expect(url, 'https://my-bucket.s3.us-east-1.amazonaws.com/uploads/2026/01/file.jpg');
      });

      test('encodes nested paths with special characters', () {
        final url = S3Utils.constructUrl(
          bucket: 'my-bucket',
          region: 'us-west-2',
          key: 'uploads/my folder/file (copy).jpg',
        );
        expect(url, 'https://my-bucket.s3.us-west-2.amazonaws.com/uploads/my%20folder/file%20%28copy%29.jpg');
      });
    });

    group('constructUrlFromCredentials', () {
      test('constructs URL from credentials', () {
        final credentials = TemporaryCredentials(
          accessKeyId: 'AKIATEST',
          secretAccessKey: 'secret',
          sessionToken: 'token',
          expiration: DateTime.now().add(const Duration(hours: 1)),
          bucket: 'test-bucket',
          region: 'eu-west-1',
        );

        final url = S3Utils.constructUrlFromCredentials(
          credentials: credentials,
          key: 'uploads/file.jpg',
        );
        expect(url, 'https://test-bucket.s3.eu-west-1.amazonaws.com/uploads/file.jpg');
      });
    });

    group('decodeUrlPath', () {
      test('decodes encoded path', () {
        final decoded = S3Utils.decodeUrlPath(
          'https://bucket.s3.us-east-1.amazonaws.com/uploads%2Ffile.jpg',
        );
        expect(decoded, 'https://bucket.s3.us-east-1.amazonaws.com/uploads/file.jpg');
      });

      test('decodes spaces', () {
        final decoded = S3Utils.decodeUrlPath(
          'https://bucket.s3.us-east-1.amazonaws.com/my%20file.jpg',
        );
        expect(decoded, 'https://bucket.s3.us-east-1.amazonaws.com/my file.jpg');
      });

      test('decodes parentheses', () {
        final decoded = S3Utils.decodeUrlPath(
          'https://bucket.s3.us-east-1.amazonaws.com/file%20%281%29.jpg',
        );
        expect(decoded, 'https://bucket.s3.us-east-1.amazonaws.com/file (1).jpg');
      });

      test('returns original on invalid URL', () {
        final decoded = S3Utils.decodeUrlPath('not a url');
        expect(decoded, 'not a url');
      });

      test('preserves already decoded URL', () {
        final decoded = S3Utils.decodeUrlPath(
          'https://bucket.s3.us-east-1.amazonaws.com/file.jpg',
        );
        expect(decoded, 'https://bucket.s3.us-east-1.amazonaws.com/file.jpg');
      });

      test('preserves port in URL', () {
        final decoded = S3Utils.decodeUrlPath(
          'https://localhost:9000/my%20file.jpg',
        );
        expect(decoded, 'https://localhost:9000/my file.jpg');
      });
    });

    group('normalizeETag', () {
      test('adds quotes to unquoted ETag', () {
        expect(S3Utils.normalizeETag('abc123'), '"abc123"');
      });

      test('preserves already quoted ETag', () {
        expect(S3Utils.normalizeETag('"abc123"'), '"abc123"');
      });

      test('handles multipart ETag format', () {
        expect(S3Utils.normalizeETag('abc123-5'), '"abc123-5"');
      });

      test('preserves already quoted multipart ETag', () {
        expect(S3Utils.normalizeETag('"abc123-5"'), '"abc123-5"');
      });
    });

    group('stripETagQuotes', () {
      test('strips quotes from ETag', () {
        expect(S3Utils.stripETagQuotes('"abc123"'), 'abc123');
      });

      test('handles unquoted ETag', () {
        expect(S3Utils.stripETagQuotes('abc123'), 'abc123');
      });

      test('strips quotes from multipart ETag', () {
        expect(S3Utils.stripETagQuotes('"abc123-5"'), 'abc123-5');
      });

      test('handles partially quoted ETag (single quote at start)', () {
        // Edge case: only one quote - should not strip
        expect(S3Utils.stripETagQuotes('"abc123'), '"abc123');
      });

      test('handles partially quoted ETag (single quote at end)', () {
        // Edge case: only one quote - should not strip
        expect(S3Utils.stripETagQuotes('abc123"'), 'abc123"');
      });
    });
  });
}
