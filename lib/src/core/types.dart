/// Core types used by all uploaders.
///
/// These types are generic and not specific to any particular uploader implementation.
/// They are used by the core Fluppy system and all uploader implementations.
library;

/// A simple cancellation token for aborting async operations.
class CancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = [];

  /// Whether cancellation has been requested.
  bool get isCancelled => _isCancelled;

  /// Request cancellation.
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in _listeners) {
      listener();
    }
    _listeners.clear();
  }

  /// Register a callback to be called when cancelled.
  void onCancel(void Function() callback) {
    if (_isCancelled) {
      callback();
    } else {
      _listeners.add(callback);
    }
  }

  /// Throws [CancelledException] if cancelled.
  void throwIfCancelled() {
    if (_isCancelled) {
      throw CancelledException();
    }
  }
}

/// Exception thrown when an operation is cancelled.
class CancelledException implements Exception {
  final String message;

  CancelledException([this.message = 'Operation was cancelled']);

  @override
  String toString() => 'CancelledException: $message';
}

/// Exception thrown when an upload is paused.
class PausedException implements Exception {
  @override
  String toString() => 'Upload was paused';
}

/// Upload progress information.
class UploadProgressInfo {
  /// Bytes uploaded so far.
  final int bytesUploaded;

  /// Total bytes to upload.
  final int bytesTotal;

  /// For multipart uploads, the number of parts uploaded.
  final int? partsUploaded;

  /// For multipart uploads, the total number of parts.
  final int? partsTotal;

  const UploadProgressInfo({
    required this.bytesUploaded,
    required this.bytesTotal,
    this.partsUploaded,
    this.partsTotal,
  });

  /// Progress as a percentage (0-100).
  double get percent => bytesTotal > 0 ? (bytesUploaded / bytesTotal) * 100 : 0;

  /// Progress as a fraction (0-1).
  double get fraction => bytesTotal > 0 ? bytesUploaded / bytesTotal : 0;

  @override
  String toString() => 'UploadProgressInfo($bytesUploaded/$bytesTotal, ${percent.toStringAsFixed(1)}%)';
}

/// Response from a completed upload.
///
/// The [body] field contains the complete response from the upload backend,
/// allowing custom data to flow through from upload callbacks.
///
/// Example:
/// ```dart
/// fluppy.events.listen((event) {
///   if (event is UploadComplete) {
///     final mediaId = event.response.body?['mediaId'];
///     final customData = event.response.body?['myCustomField'];
///   }
/// });
/// ```
class UploadResponse {
  /// The URL to the uploaded file (if available).
  final String? location;

  /// The complete response body from the upload backend.
  ///
  /// This field contains any custom data returned by your upload callbacks
  /// (e.g., `completeMultipartUpload`). Use this to access backend-specific
  /// response data like media IDs, blob references, or custom metadata.
  ///
  /// Example:
  /// ```dart
  /// final response = UploadResponse(
  ///   location: 'https://example.com/file.jpg',
  ///   body: {
  ///     'mediaId': '12345',
  ///     'eTag': '"abc123"',
  ///     'key': 'uploads/file.jpg',
  ///     'customField': 'value',
  ///   },
  /// );
  /// ```
  final Map<String, dynamic>? body;

  const UploadResponse({
    this.location,
    this.body,
  });

  @override
  String toString() => 'UploadResponse(location: $location, body: $body)';
}
