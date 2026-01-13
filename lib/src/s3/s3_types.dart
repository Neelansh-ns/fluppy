import 'dart:typed_data';

import '../core/types.dart';

class S3MultipartState {
  /// The S3 upload ID for multipart uploads.
  String? uploadId;

  /// The S3 object key.
  String? key;

  /// Parts that have been uploaded.
  final List<S3Part> uploadedParts;

  /// Whether this is a multipart upload.
  bool isMultipart = false;

  S3MultipartState({
    this.uploadId,
    this.key,
    List<S3Part>? uploadedParts,
    this.isMultipart = false,
  }) : uploadedParts = uploadedParts ?? [];

  /// Resets all S3 multipart state.
  void reset() {
    uploadId = null;
    key = null;
    uploadedParts.clear();
    isMultipart = false;
  }
}

/// Parameters for single-part (non-multipart) uploads.
///
/// Returned by [S3UploaderOptions.getUploadParameters] to configure
/// how a file should be uploaded using a presigned URL.
class UploadParameters {
  /// HTTP method to use for the upload ('PUT' or 'POST').
  final String method;

  /// The presigned URL to upload to.
  final String url;

  /// Optional headers to include with the upload request.
  /// For PUT uploads, include 'Content-Type' to match the signed type.
  final Map<String, String>? headers;

  /// Optional form fields for POST uploads with policy documents.
  /// Leave empty for presigned PUT uploads.
  final Map<String, String>? fields;

  /// Optional expiration time in seconds.
  ///
  /// When set, this is used to:
  /// - Set a timeout on the HTTP request
  /// - Detect expired presigned URLs (403 responses)
  ///
  /// Typically matches the presigned URL expiration time.
  final int? expires;

  const UploadParameters({required this.method, required this.url, this.headers, this.fields, this.expires});

  @override
  String toString() => 'UploadParameters(method: $method, url: $url, expires: $expires)';
}

/// Options passed to [S3UploaderOptions.getUploadParameters].
class UploadOptions {
  /// Cancellation signal for the request.
  final CancellationToken? signal;

  const UploadOptions({this.signal});
}

/// Result from initiating a multipart upload.
///
/// Returned by [S3UploaderOptions.createMultipartUpload].
class CreateMultipartUploadResult {
  /// The S3 UploadId for this multipart upload.
  final String uploadId;

  /// The object key in the S3 bucket.
  final String key;

  const CreateMultipartUploadResult({required this.uploadId, required this.key});

  @override
  String toString() => 'CreateMultipartUploadResult(uploadId: $uploadId, key: $key)';
}

/// Represents a single part in an S3 multipart upload.
///
/// Used for tracking uploaded parts and completing the upload.
class S3Part {
  /// The part number (1-indexed, S3 requires 1-10000).
  final int partNumber;

  /// Size of the part in bytes.
  final int size;

  /// The ETag returned by S3 after uploading the part.
  final String eTag;

  const S3Part({required this.partNumber, required this.size, required this.eTag});

  /// Creates an S3Part from JSON (typically from listParts response).
  factory S3Part.fromJson(Map<String, dynamic> json) {
    return S3Part(partNumber: json['PartNumber'] as int, size: json['Size'] as int, eTag: json['ETag'] as String);
  }

  /// Converts to JSON for API requests.
  Map<String, dynamic> toJson() => {'PartNumber': partNumber, 'Size': size, 'ETag': eTag};

  @override
  String toString() => 'S3Part(partNumber: $partNumber, size: $size)';
}

/// Options for listing parts of a multipart upload.
class ListPartsOptions {
  /// The S3 UploadId.
  final String uploadId;

  /// The object key.
  final String key;

  /// Cancellation signal.
  final CancellationToken? signal;

  const ListPartsOptions({required this.uploadId, required this.key, this.signal});
}

/// Options for signing a single part.
class SignPartOptions {
  /// The S3 UploadId.
  final String uploadId;

  /// The object key.
  final String key;

  /// Part number (1-indexed).
  final int partNumber;

  /// The data to be uploaded for this part.
  final Uint8List body;

  /// Cancellation signal.
  final CancellationToken? signal;

  const SignPartOptions({
    required this.uploadId,
    required this.key,
    required this.partNumber,
    required this.body,
    this.signal,
  });

  @override
  String toString() => 'SignPartOptions(uploadId: $uploadId, partNumber: $partNumber)';
}

/// Result from signing a part.
class SignPartResult {
  /// The presigned URL for uploading this part.
  final String url;

  /// Optional headers to include with the part upload.
  final Map<String, String>? headers;

  /// Optional expiration time in seconds.
  ///
  /// When set, this is used to:
  /// - Set a timeout on the HTTP request
  /// - Detect expired presigned URLs (403 responses)
  final int? expires;

  const SignPartResult({required this.url, this.headers, this.expires});

  @override
  String toString() => 'SignPartResult(url: $url, expires: $expires)';
}

/// Options for aborting a multipart upload.
class AbortMultipartOptions {
  /// The S3 UploadId.
  final String uploadId;

  /// The object key.
  final String key;

  /// Cancellation signal.
  final CancellationToken? signal;

  const AbortMultipartOptions({required this.uploadId, required this.key, this.signal});
}

/// Options for completing a multipart upload.
class CompleteMultipartOptions {
  /// The S3 UploadId.
  final String uploadId;

  /// The object key.
  final String key;

  /// List of uploaded parts with ETags.
  final List<S3Part> parts;

  /// Cancellation signal.
  final CancellationToken? signal;

  const CompleteMultipartOptions({required this.uploadId, required this.key, required this.parts, this.signal});
}

/// Result from completing a multipart upload.
class CompleteMultipartResult {
  /// The public URL to the uploaded file (if available).
  final String? location;

  /// The ETag of the completed object.
  final String? eTag;

  const CompleteMultipartResult({this.location, this.eTag});

  @override
  String toString() => 'CompleteMultipartResult(location: $location)';
}

/// Options for getting temporary security credentials.
class CredentialsOptions {
  /// Cancellation signal.
  final CancellationToken? signal;

  const CredentialsOptions({this.signal});
}

/// Temporary AWS credentials for direct uploads.
///
/// Using temporary credentials reduces request overhead as users get
/// a single token for bucket operations instead of signing each request.
class TemporaryCredentials {
  /// AWS Access Key ID.
  final String accessKeyId;

  /// AWS Secret Access Key.
  final String secretAccessKey;

  /// AWS Session Token.
  final String sessionToken;

  /// When these credentials expire.
  final DateTime expiration;

  /// The S3 bucket name.
  final String bucket;

  /// The AWS region.
  final String region;

  const TemporaryCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.sessionToken,
    required this.expiration,
    required this.bucket,
    required this.region,
  });

  /// Creates credentials from JSON (typically from STS response).
  factory TemporaryCredentials.fromJson(Map<String, dynamic> json) {
    final credentials = json['credentials'] as Map<String, dynamic>? ?? json;
    return TemporaryCredentials(
      accessKeyId: credentials['AccessKeyId'] as String,
      secretAccessKey: credentials['SecretAccessKey'] as String,
      sessionToken: credentials['SessionToken'] as String,
      expiration: DateTime.parse(credentials['Expiration'] as String),
      bucket: json['bucket'] as String,
      region: json['region'] as String,
    );
  }

  /// Whether these credentials have expired.
  bool get isExpired => DateTime.now().isAfter(expiration);

  @override
  String toString() => 'TemporaryCredentials(bucket: $bucket, region: $region, expires: $expiration)';
}

/// Options for uploading part bytes.
///
/// Used by [UploadPartBytesCallback] to provide all necessary
/// information for uploading a part.
class UploadPartBytesOptions {
  /// The presigned URL to upload to.
  final String url;

  /// The method to use ('PUT' or 'POST').
  final String method;

  /// Headers to include in the request.
  final Map<String, String>? headers;

  /// The data to upload.
  final Uint8List body;

  /// Size of the data being uploaded.
  final int size;

  /// Optional expiration time in seconds.
  final int? expires;

  /// Cancellation signal.
  final CancellationToken? signal;

  /// Progress callback.
  final void Function(int bytesUploaded, int bytesTotal)? onProgress;

  /// Called when upload completes successfully.
  final void Function(String eTag)? onComplete;

  const UploadPartBytesOptions({
    required this.url,
    this.method = 'PUT',
    this.headers,
    required this.body,
    required this.size,
    this.expires,
    this.signal,
    this.onProgress,
    this.onComplete,
  });
}

/// Result from uploading part bytes.
class UploadPartBytesResult {
  /// The ETag returned by S3.
  final String eTag;

  /// The location URL (for POST uploads).
  final String? location;

  /// All response headers.
  final Map<String, String> headers;

  const UploadPartBytesResult({required this.eTag, this.location, this.headers = const {}});
}
