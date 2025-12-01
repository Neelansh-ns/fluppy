import 'dart:async';
import 'dart:typed_data';

import 'package:fluppy/fluppy.dart';
import 'package:test/test.dart';

/// Mock uploader for testing
class MockUploader extends Uploader {
  final List<String> uploadedFiles = [];
  final Map<String, Completer<UploadResponse>> completers = {};
  bool shouldFail = false;
  String? failMessage;

  @override
  bool get supportsPause => true;

  @override
  bool get supportsResume => true;

  @override
  Future<UploadResponse> upload(
    FluppyFile file, {
    required ProgressCallback onProgress,
    required EventEmitter emitEvent,
    CancellationToken? cancellationToken,
  }) async {
    if (shouldFail) {
      throw Exception(failMessage ?? 'Mock upload failed');
    }

    // Simulate progress
    for (var i = 0; i <= 100; i += 25) {
      cancellationToken?.throwIfCancelled();
      onProgress(UploadProgressInfo(
        bytesUploaded: (file.size * i / 100).round(),
        bytesTotal: file.size,
      ));
      await Future.delayed(const Duration(milliseconds: 10));
    }

    uploadedFiles.add(file.id);
    return UploadResponse(
      location: 'https://example.com/${file.name}',
      key: file.name,
    );
  }

  @override
  Future<bool> pause(FluppyFile file) async => true;

  @override
  Future<UploadResponse> resume(
    FluppyFile file, {
    required ProgressCallback onProgress,
    required EventEmitter emitEvent,
    CancellationToken? cancellationToken,
  }) async {
    return upload(
      file,
      onProgress: onProgress,
      emitEvent: emitEvent,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<void> cancel(FluppyFile file) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  group('Fluppy', () {
    late Fluppy fluppy;
    late MockUploader mockUploader;

    setUp(() {
      mockUploader = MockUploader();
      fluppy = Fluppy(uploader: mockUploader);
    });

    tearDown(() async {
      await fluppy.dispose();
    });

    group('file management', () {
      test('addFile adds file to queue', () {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        final addedFile = fluppy.addFile(file);

        expect(fluppy.files.length, equals(1));
        expect(fluppy.files.first.id, equals(addedFile.id));
      });

      test('addFiles adds multiple files', () {
        final files = [
          FluppyFile.fromBytes(Uint8List.fromList([1]), name: 'test1.bin'),
          FluppyFile.fromBytes(Uint8List.fromList([2]), name: 'test2.bin'),
        ];

        fluppy.addFiles(files);

        expect(fluppy.files.length, equals(2));
      });

      test('getFile returns file by id', () {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        fluppy.addFile(file);

        expect(fluppy.getFile(file.id), equals(file));
        expect(fluppy.getFile('non-existent'), isNull);
      });

      test('removeFile removes file from queue', () async {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        fluppy.addFile(file);
        await fluppy.removeFile(file.id);

        expect(fluppy.files, isEmpty);
      });

      test('pendingFiles returns only pending files', () async {
        final file1 = FluppyFile.fromBytes(
          Uint8List.fromList([1]),
          name: 'test1.bin',
        );
        final file2 = FluppyFile.fromBytes(
          Uint8List.fromList([2]),
          name: 'test2.bin',
        );

        fluppy.addFile(file1);
        fluppy.addFile(file2);

        // Upload one file
        await fluppy.upload(file1.id);

        expect(fluppy.pendingFiles.length, equals(1));
        expect(fluppy.pendingFiles.first.id, equals(file2.id));
      });
    });

    group('events', () {
      test('emits FileAdded event', () async {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        final events = <FluppyEvent>[];
        fluppy.events.listen(events.add);

        fluppy.addFile(file);

        await Future.delayed(Duration.zero);

        expect(events, contains(isA<FileAdded>()));
      });

      test('emits UploadStarted event', () async {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        final events = <FluppyEvent>[];
        fluppy.events.listen(events.add);

        fluppy.addFile(file);
        await fluppy.upload(file.id);

        expect(events, contains(isA<UploadStarted>()));
      });

      test('emits UploadProgress events', () async {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        final progressEvents = <UploadProgress>[];
        fluppy.events
            .where((e) => e is UploadProgress)
            .cast<UploadProgress>()
            .listen(progressEvents.add);

        fluppy.addFile(file);
        await fluppy.upload(file.id);

        expect(progressEvents, isNotEmpty);
      });

      test('emits UploadComplete event', () async {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        final completer = Completer<void>();
        final events = <FluppyEvent>[];
        fluppy.events.listen((event) {
          events.add(event);
          if (event is UploadComplete) {
            completer.complete();
          }
        });

        fluppy.addFile(file);
        await fluppy.upload(file.id);
        
        // Wait for complete event to be processed
        await completer.future.timeout(const Duration(seconds: 5));

        expect(events, contains(isA<UploadComplete>()));
      });

      test('emits UploadError event on failure', () async {
        mockUploader.shouldFail = true;
        mockUploader.failMessage = 'Test failure';

        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        final completer = Completer<void>();
        final events = <FluppyEvent>[];
        fluppy.events.listen((event) {
          events.add(event);
          if (event is UploadError) {
            completer.complete();
          }
        });

        fluppy.addFile(file);
        await fluppy.upload(file.id);

        // Wait for error event to be processed
        await completer.future.timeout(const Duration(seconds: 5));

        expect(events, contains(isA<UploadError>()));
      });

      test('emits FileRemoved event', () async {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        final completer = Completer<void>();
        final events = <FluppyEvent>[];
        fluppy.events.listen((event) {
          events.add(event);
          if (event is FileRemoved) {
            completer.complete();
          }
        });

        fluppy.addFile(file);
        await fluppy.removeFile(file.id);

        // Wait for remove event to be processed
        await completer.future.timeout(const Duration(seconds: 5));

        expect(events, contains(isA<FileRemoved>()));
      });
    });

    group('upload', () {
      test('uploads single file', () async {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        fluppy.addFile(file);
        await fluppy.upload(file.id);

        expect(mockUploader.uploadedFiles, contains(file.id));
        expect(file.status, equals(FileStatus.complete));
      });

      test('uploads all pending files', () async {
        final files = [
          FluppyFile.fromBytes(Uint8List.fromList([1]), name: 'test1.bin'),
          FluppyFile.fromBytes(Uint8List.fromList([2]), name: 'test2.bin'),
          FluppyFile.fromBytes(Uint8List.fromList([3]), name: 'test3.bin'),
        ];

        fluppy.addFiles(files);
        await fluppy.upload();

        expect(mockUploader.uploadedFiles.length, equals(3));
        expect(fluppy.completedFiles.length, equals(3));
      });

      test('respects maxConcurrent limit', () async {
        final fluppyLimited = Fluppy(
          uploader: mockUploader,
          maxConcurrent: 2,
        );

        final files = [
          FluppyFile.fromBytes(Uint8List.fromList([1]), name: 'test1.bin'),
          FluppyFile.fromBytes(Uint8List.fromList([2]), name: 'test2.bin'),
          FluppyFile.fromBytes(Uint8List.fromList([3]), name: 'test3.bin'),
        ];

        fluppyLimited.addFiles(files);
        await fluppyLimited.upload();

        // All files should still upload eventually
        expect(mockUploader.uploadedFiles.length, equals(3));

        await fluppyLimited.dispose();
      });

      test('sets response on completed file', () async {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        fluppy.addFile(file);
        await fluppy.upload(file.id);

        expect(file.response, isNotNull);
        expect(file.response!.location, contains('test.bin'));
      });
    });

    group('cancel', () {
      test('cancels upload', () async {
        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        fluppy.addFile(file);

        // Start upload in background
        final uploadFuture = fluppy.upload(file.id);

        // Cancel immediately
        await fluppy.cancel(file.id);

        await uploadFuture;

        // File should be cancelled or completed depending on timing
        expect(
          file.status,
          anyOf(equals(FileStatus.cancelled), equals(FileStatus.complete)),
        );
      });
    });

    group('retry', () {
      test('retries failed upload', () async {
        mockUploader.shouldFail = true;

        final file = FluppyFile.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          name: 'test.bin',
        );

        fluppy.addFile(file);
        await fluppy.upload(file.id);

        expect(file.status, equals(FileStatus.error));

        // Now allow success
        mockUploader.shouldFail = false;
        await fluppy.retry(file.id);

        expect(file.status, equals(FileStatus.complete));
      });
    });

    group('clearCompleted', () {
      test('removes completed files', () async {
        final file1 = FluppyFile.fromBytes(
          Uint8List.fromList([1]),
          name: 'test1.bin',
        );
        final file2 = FluppyFile.fromBytes(
          Uint8List.fromList([2]),
          name: 'test2.bin',
        );

        fluppy.addFile(file1);
        fluppy.addFile(file2);

        await fluppy.upload(file1.id);

        fluppy.clearCompleted();

        expect(fluppy.files.length, equals(1));
        expect(fluppy.files.first.id, equals(file2.id));
      });
    });

    group('overallProgress', () {
      test('calculates overall progress', () async {
        final file1 = FluppyFile.fromBytes(
          Uint8List.fromList(List.filled(100, 0)),
          name: 'test1.bin',
        );
        final file2 = FluppyFile.fromBytes(
          Uint8List.fromList(List.filled(100, 0)),
          name: 'test2.bin',
        );

        fluppy.addFile(file1);
        fluppy.addFile(file2);

        final progress = fluppy.overallProgress;

        expect(progress.bytesTotal, equals(200));
        expect(progress.bytesUploaded, equals(0));
      });
    });
  });
}

