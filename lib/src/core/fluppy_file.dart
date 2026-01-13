part of 'fluppy.dart';

const _uuid = Uuid();

/// The status of a file in the upload queue.
enum FileStatus {
  /// File has been added but upload hasn't started.
  pending,

  /// File is currently being uploaded.
  uploading,

  /// Upload is paused.
  paused,

  /// Upload completed successfully.
  complete,

  /// Upload failed with an error.
  error,

  /// Upload was cancelled.
  cancelled,
}

/// The source type of a file.
enum FileSourceType {
  /// File from local filesystem path.
  path,

  /// File from raw bytes.
  bytes,

  /// File from a stream (for large files).
  stream,
}

/// Represents a file to be uploaded.
///
/// Use the factory constructors to create files from different sources:
/// - [FluppyFile.fromPath] for local files
/// - [FluppyFile.fromBytes] for in-memory data
/// - [FluppyFile.fromStream] for streaming large files
class FluppyFile {
  /// Unique identifier for this file.
  final String id;

  /// The file name.
  final String name;

  /// File size in bytes.
  final int size;

  /// MIME type of the file.
  final String? type;

  /// The source type.
  final FileSourceType sourceType;

  /// Path to the file (if [sourceType] is [FileSourceType.path]).
  final String? path;

  /// Raw bytes (if [sourceType] is [FileSourceType.bytes]).
  final Uint8List? bytes;

  /// Stream provider (if [sourceType] is [FileSourceType.stream]).
  final Stream<List<int>> Function()? streamProvider;

  FileStatus _status;

  /// Upload progress information.
  UploadProgressInfo? progress;

  /// Error message if status is [FileStatus.error].
  String? errorMessage;

  /// The error object if status is [FileStatus.error].
  Object? error;

  /// Custom metadata associated with this file.
  final Map<String, dynamic> metadata;

  /// Response from the upload (after completion).
  UploadResponse? response;

  /// Current upload status (read-only).
  ///
  /// Status can only be changed through Fluppy methods:
  /// - [Fluppy.upload] - sets status to uploading
  /// - [Fluppy.pause] - sets status to paused
  /// - [Fluppy.cancel] - sets status to cancelled
  /// - [Fluppy.retry] - resets status to pending
  FileStatus get status => _status;

  FluppyFile._({
    required this.id,
    required this.name,
    required this.size,
    required this.sourceType,
    this.type,
    this.path,
    this.bytes,
    this.streamProvider,
    Map<String, dynamic>? metadata,
  })  : _status = FileStatus.pending,
        metadata = metadata ?? {};

  /// Creates a FluppyFile from a local filesystem path.
  ///
  /// ```dart
  /// final file = FluppyFile.fromPath('/path/to/video.mp4');
  /// ```
  factory FluppyFile.fromPath(
    String filePath, {
    String? id,
    String? name,
    String? type,
    Map<String, dynamic>? metadata,
  }) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw ArgumentError('File does not exist: $filePath');
    }

    final fileName = name ?? p.basename(filePath);
    final mimeType = type ?? lookupMimeType(filePath);
    final fileSize = file.lengthSync();

    return FluppyFile._(
      id: id ?? _uuid.v4(),
      name: fileName,
      size: fileSize,
      type: mimeType,
      sourceType: FileSourceType.path,
      path: filePath,
      metadata: metadata,
    );
  }

  /// Creates a FluppyFile from raw bytes.
  ///
  /// ```dart
  /// final file = FluppyFile.fromBytes(
  ///   imageBytes,
  ///   name: 'photo.jpg',
  ///   type: 'image/jpeg',
  /// );
  /// ```
  factory FluppyFile.fromBytes(
    Uint8List data, {
    required String name,
    String? id,
    String? type,
    Map<String, dynamic>? metadata,
  }) {
    final mimeType = type ?? lookupMimeType(name);

    return FluppyFile._(
      id: id ?? _uuid.v4(),
      name: name,
      size: data.length,
      type: mimeType,
      sourceType: FileSourceType.bytes,
      bytes: data,
      metadata: metadata,
    );
  }

  /// Creates a FluppyFile from a stream provider.
  ///
  /// Use this for large files to avoid loading them entirely into memory.
  /// The provider function will be called to create a new stream when needed.
  ///
  /// ```dart
  /// final file = FluppyFile.fromStream(
  ///   () => largeFile.openRead(),
  ///   name: 'large-video.mp4',
  ///   size: largeFile.lengthSync(),
  /// );
  /// ```
  factory FluppyFile.fromStream(
    Stream<List<int>> Function() streamProvider, {
    required String name,
    required int size,
    String? id,
    String? type,
    Map<String, dynamic>? metadata,
  }) {
    final mimeType = type ?? lookupMimeType(name);

    return FluppyFile._(
      id: id ?? _uuid.v4(),
      name: name,
      size: size,
      type: mimeType,
      sourceType: FileSourceType.stream,
      streamProvider: streamProvider,
      metadata: metadata,
    );
  }

  /// Gets the file data as bytes.
  ///
  /// For path-based files, reads the file into memory.
  /// For stream-based files, collects the stream into bytes.
  Future<Uint8List> getBytes() async {
    switch (sourceType) {
      case FileSourceType.bytes:
        return bytes!;
      case FileSourceType.path:
        return await File(path!).readAsBytes();
      case FileSourceType.stream:
        final chunks = await streamProvider!().toList();
        final totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
        final result = Uint8List(totalLength);
        var offset = 0;
        for (final chunk in chunks) {
          result.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }
        return result;
    }
  }

  /// Gets a stream of the file data.
  Stream<List<int>> getStream() {
    switch (sourceType) {
      case FileSourceType.bytes:
        return Stream.value(bytes!);
      case FileSourceType.path:
        return File(path!).openRead();
      case FileSourceType.stream:
        return streamProvider!();
    }
  }

  /// Gets a chunk of the file data.
  ///
  /// [start] is the byte offset to start from.
  /// [end] is the byte offset to end at (exclusive).
  Future<Uint8List> getChunk(int start, int end) async {
    switch (sourceType) {
      case FileSourceType.bytes:
        return Uint8List.sublistView(bytes!, start, end);
      case FileSourceType.path:
        final file = File(path!);
        final raf = await file.open();
        try {
          await raf.setPosition(start);
          final chunk = await raf.read(end - start);
          return chunk;
        } finally {
          await raf.close();
        }
      case FileSourceType.stream:
        // For streams, we need to read and skip
        final chunks = <int>[];
        var currentPos = 0;
        await for (final chunk in streamProvider!()) {
          for (final byte in chunk) {
            if (currentPos >= start && currentPos < end) {
              chunks.add(byte);
            }
            currentPos++;
            if (currentPos >= end) break;
          }
          if (currentPos >= end) break;
        }
        return Uint8List.fromList(chunks);
    }
  }

  void _updateStatus(FileStatus newStatus, {String? errorMsg, Object? err}) {
    _status = newStatus;
    if (newStatus == FileStatus.error) {
      errorMessage = errorMsg;
      error = err;
    }
  }

  /// Updates progress information.
  void updateProgress({
    required int bytesUploaded,
    int? partsUploaded,
    int? partsTotal,
  }) {
    progress = UploadProgressInfo(
      bytesUploaded: bytesUploaded,
      bytesTotal: size,
      partsUploaded: partsUploaded,
      partsTotal: partsTotal,
    );
  }

  /// Resets the file for retry.
  void reset() {
    _status = FileStatus.pending;
    progress = null;
    errorMessage = null;
    error = null;
    response = null;
    // Keep multipart state for resume capability
  }

  void _updateStatusInternal(FileStatus newStatus, {String? errorMsg, Object? err}) {
    _updateStatus(newStatus, errorMsg: errorMsg, err: err);
  }

  void _setStatusInternal(FileStatus value) {
    _status = value;
  }

  @override
  String toString() => 'FluppyFile(id: $id, name: $name, status: $status)';
}
