import 'package:fluppy/fluppy.dart';
import 'package:test/test.dart';

void main() {
  group('UploadResponse', () {
    test('body field contains custom data', () {
      const response = UploadResponse(
        location: 'https://example.com/file.jpg',
        body: {
          'mediaId': '12345',
          'blobId': 'blob-abc',
          'customField': 'value',
        },
      );

      expect(response.body?['mediaId'], '12345');
      expect(response.body?['blobId'], 'blob-abc');
      expect(response.body?['customField'], 'value');
    });

    test('body includes S3 fields', () {
      const response = UploadResponse(
        location: 'https://example.com/file.jpg',
        body: {
          'eTag': '"abc123"',
          'key': 'uploads/file.jpg',
        },
      );

      expect(response.body?['eTag'], '"abc123"');
      expect(response.body?['key'], 'uploads/file.jpg');
    });

    test('body can be null', () {
      const response = UploadResponse(location: 'https://example.com/file.jpg');
      expect(response.body, isNull);
    });

    test('location can be null', () {
      const response = UploadResponse(
        body: {'key': 'test.jpg'},
      );
      expect(response.location, isNull);
      expect(response.body?['key'], 'test.jpg');
    });

    test('toString includes body', () {
      const response = UploadResponse(
        location: 'https://example.com/file.jpg',
        body: {'mediaId': '123'},
      );
      final str = response.toString();
      expect(str, contains('location'));
      expect(str, contains('body'));
    });
  });

  group('CompleteMultipartResult', () {
    test('body field passes custom data', () {
      const result = CompleteMultipartResult(
        location: 'https://example.com/file.jpg',
        eTag: '"abc123"',
        body: {
          'mediaId': '12345',
          'processingStatus': 'complete',
        },
      );

      expect(result.body?['mediaId'], '12345');
      expect(result.body?['processingStatus'], 'complete');
    });

    test('body can be null for backwards compatibility', () {
      const result = CompleteMultipartResult(
        location: 'https://example.com/file.jpg',
        eTag: '"abc123"',
      );

      expect(result.body, isNull);
      expect(result.location, 'https://example.com/file.jpg');
      expect(result.eTag, '"abc123"');
    });

    test('all fields can be null', () {
      const result = CompleteMultipartResult();

      expect(result.location, isNull);
      expect(result.eTag, isNull);
      expect(result.body, isNull);
    });

    test('toString includes body', () {
      const result = CompleteMultipartResult(
        location: 'https://example.com/file.jpg',
        body: {'mediaId': '123'},
      );
      final str = result.toString();
      expect(str, contains('location'));
      expect(str, contains('body'));
    });
  });
}
