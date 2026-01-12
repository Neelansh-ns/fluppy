import 'dart:io';
import 'dart:typed_data';

import 'package:fluppy/fluppy.dart';
import 'package:test/test.dart';

void main() {
  group('FluppyFile', () {
    group('fromBytes', () {
      test('creates file with correct properties', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final file = FluppyFile.fromBytes(
          bytes,
          name: 'test.bin',
          type: 'application/octet-stream',
        );

        expect(file.name, equals('test.bin'));
        expect(file.size, equals(5));
        expect(file.type, equals('application/octet-stream'));
        expect(file.sourceType, equals(FileSourceType.bytes));
        expect(file.status, equals(FileStatus.pending));
      });
    });

    group('fromPath', () {
      late File tempFile;

      setUp(() async {
        tempFile = File('${Directory.systemTemp.path}/fluppy_test_file.txt');
        await tempFile.writeAsString('Hello, World!');
      });

      tearDown(() async {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      });

      test('creates file with correct properties', () {
        final file = FluppyFile.fromPath(tempFile.path);

        expect(file.name, equals('fluppy_test_file.txt'));
        expect(file.size, equals(13)); // "Hello, World!".length
        expect(file.type, equals('text/plain'));
        expect(file.sourceType, equals(FileSourceType.path));
        expect(file.path, equals(tempFile.path));
      });

      test('throws for non-existent file', () {
        expect(
          () => FluppyFile.fromPath('/non/existent/file.txt'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('getBytes returns file contents', () async {
        final file = FluppyFile.fromPath(tempFile.path);
        final bytes = await file.getBytes();

        expect(String.fromCharCodes(bytes), equals('Hello, World!'));
      });
    });

    group('fromStream', () {
      test('creates file with correct properties', () {
        final file = FluppyFile.fromStream(
          () => Stream.value([1, 2, 3, 4, 5]),
          name: 'test.bin',
          size: 5,
        );

        expect(file.name, equals('test.bin'));
        expect(file.size, equals(5));
        expect(file.sourceType, equals(FileSourceType.stream));
      });

      test('getStream returns data', () async {
        final file = FluppyFile.fromStream(
          () => Stream.value([1, 2, 3, 4, 5]),
          name: 'test.bin',
          size: 5,
        );

        final chunks = await file.getStream().toList();
        expect(chunks.first, equals([1, 2, 3, 4, 5]));
      });
    });

    group('status management', () {
      test('updateStatus changes status', () {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        file.updateStatus(FileStatus.uploading);
        expect(file.status, equals(FileStatus.uploading));

        file.updateStatus(FileStatus.complete);
        expect(file.status, equals(FileStatus.complete));
      });

      test('updateStatus with error sets error info', () {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        final error = Exception('Test error');
        file.updateStatus(
          FileStatus.error,
          errorMsg: 'Upload failed',
          err: error,
        );

        expect(file.status, equals(FileStatus.error));
        expect(file.errorMessage, equals('Upload failed'));
        expect(file.error, equals(error));
      });

      test('reset clears error and progress but keeps multipart state', () {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        file.updateStatus(FileStatus.error, errorMsg: 'Error');
        file.uploadId = 'test-upload-id';
        file.key = 'test-key';
        file.uploadedParts.add(const S3Part(partNumber: 1, size: 100, eTag: 'etag'));

        file.reset();

        expect(file.status, equals(FileStatus.pending));
        expect(file.errorMessage, isNull);
        expect(file.uploadId, equals('test-upload-id'));
        expect(file.uploadedParts.length, equals(1));
      });

      test('fullReset clears everything', () {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        file.updateStatus(FileStatus.error, errorMsg: 'Error');
        file.uploadId = 'test-upload-id';
        file.key = 'test-key';
        file.uploadedParts.add(const S3Part(partNumber: 1, size: 100, eTag: 'etag'));
        file.isMultipart = true;

        file.fullReset();

        expect(file.status, equals(FileStatus.pending));
        expect(file.uploadId, isNull);
        expect(file.key, isNull);
        expect(file.uploadedParts, isEmpty);
        expect(file.isMultipart, isFalse);
      });
    });

    group('progress', () {
      test('updateProgress sets progress info', () {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList(List.filled(100, 0)),
          name: 'test.bin',
        );

        file.updateProgress(bytesUploaded: 50);

        expect(file.progress, isNotNull);
        expect(file.progress!.bytesUploaded, equals(50));
        expect(file.progress!.bytesTotal, equals(100));
        expect(file.progress!.percent, equals(50.0));
      });

      test('updateProgress with parts info', () {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList(List.filled(100, 0)),
          name: 'test.bin',
        );

        file.updateProgress(
          bytesUploaded: 50,
          partsUploaded: 2,
          partsTotal: 4,
        );

        expect(file.progress!.partsUploaded, equals(2));
        expect(file.progress!.partsTotal, equals(4));
      });
    });

    group('metadata', () {
      test('allows custom metadata', () {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
          metadata: {'customField': 'customValue'},
        );

        expect(file.metadata['customField'], equals('customValue'));
      });
    });
  });
}
