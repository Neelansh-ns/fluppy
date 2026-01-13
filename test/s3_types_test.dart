import 'package:fluppy/fluppy.dart';
import 'package:fluppy/src/core/types.dart'; // Import for generic types
import 'package:test/test.dart';

void main() {
  group('UploadParameters', () {
    test('creates with required and optional fields', () {
      const params = UploadParameters(
        method: 'POST',
        url: 'https://example.com/upload',
        headers: {'Content-Type': 'image/png'},
        fields: {'key': 'value'},
      );

      expect(params.method, equals('POST'));
      expect(params.url, equals('https://example.com/upload'));
      expect(params.headers, equals({'Content-Type': 'image/png'}));
      expect(params.fields, equals({'key': 'value'}));
    });
  });

  group('S3Part', () {
    test('fromJson parses correctly', () {
      final json = {
        'PartNumber': 2,
        'Size': 1024,
        'ETag': '"def456"',
      };

      final part = S3Part.fromJson(json);

      expect(part.partNumber, equals(2));
      expect(part.size, equals(1024));
      expect(part.eTag, equals('"def456"'));
    });

    test('toJson serializes correctly', () {
      const part = S3Part(
        partNumber: 3,
        size: 2048,
        eTag: '"ghi789"',
      );

      final json = part.toJson();

      expect(json['PartNumber'], equals(3));
      expect(json['Size'], equals(2048));
      expect(json['ETag'], equals('"ghi789"'));
    });
  });

  group('TemporaryCredentials', () {
    test('isExpired returns true for past expiration', () {
      final credentials = TemporaryCredentials(
        accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
        secretAccessKey: 'secret',
        sessionToken: 'token',
        expiration: DateTime.now().subtract(const Duration(hours: 1)),
        bucket: 'my-bucket',
        region: 'us-east-1',
      );

      expect(credentials.isExpired, isTrue);
    });

    test('fromJson parses correctly', () {
      final json = {
        'credentials': {
          'AccessKeyId': 'AKID',
          'SecretAccessKey': 'SECRET',
          'SessionToken': 'TOKEN',
          'Expiration': '2024-12-31T23:59:59Z',
        },
        'bucket': 'test-bucket',
        'region': 'eu-west-1',
      };

      final credentials = TemporaryCredentials.fromJson(json);

      expect(credentials.accessKeyId, equals('AKID'));
      expect(credentials.secretAccessKey, equals('SECRET'));
      expect(credentials.bucket, equals('test-bucket'));
      expect(credentials.region, equals('eu-west-1'));
    });
  });

  group('CancellationToken', () {
    test('starts not cancelled', () {
      final token = CancellationToken();
      expect(token.isCancelled, isFalse);
    });

    test('cancel sets isCancelled to true', () {
      final token = CancellationToken();
      token.cancel();
      expect(token.isCancelled, isTrue);
    });

    test('throwIfCancelled throws when cancelled', () {
      final token = CancellationToken();
      token.cancel();

      expect(
        () => token.throwIfCancelled(),
        throwsA(isA<CancelledException>()),
      );
    });

    test('onCancel callback is called when cancelled', () {
      final token = CancellationToken();
      var called = false;

      token.onCancel(() => called = true);
      token.cancel();

      expect(called, isTrue);
    });

    test('onCancel callback is called immediately if already cancelled', () {
      final token = CancellationToken();
      token.cancel();

      var called = false;
      token.onCancel(() => called = true);

      expect(called, isTrue);
    });
  });

  group('UploadProgressInfo', () {
    test('calculates percent correctly', () {
      const progress = UploadProgressInfo(
        bytesUploaded: 50,
        bytesTotal: 100,
      );

      expect(progress.percent, equals(50.0));
      expect(progress.fraction, equals(0.5));
    });

    test('handles zero total', () {
      const progress = UploadProgressInfo(
        bytesUploaded: 0,
        bytesTotal: 0,
      );

      expect(progress.percent, equals(0.0));
      expect(progress.fraction, equals(0.0));
    });

    test('includes part info when provided', () {
      const progress = UploadProgressInfo(
        bytesUploaded: 50,
        bytesTotal: 100,
        partsUploaded: 2,
        partsTotal: 4,
      );

      expect(progress.partsUploaded, equals(2));
      expect(progress.partsTotal, equals(4));
    });
  });
}
