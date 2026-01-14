import '../core/fluppy.dart' show FluppyFile;
import 's3_types.dart';

/// Signature for the shouldUseMultipart callback.
typedef ShouldUseMultipartCallback = bool Function(FluppyFile file);

/// Signature for the getChunkSize callback.
typedef GetChunkSizeCallback = int Function(FluppyFile file);

/// Signature for the getUploadParameters callback.
typedef GetUploadParametersCallback = Future<UploadParameters> Function(
  FluppyFile file,
  UploadOptions options,
);

/// Signature for the createMultipartUpload callback.
typedef CreateMultipartUploadCallback = Future<CreateMultipartUploadResult> Function(FluppyFile file);

/// Signature for the listParts callback.
typedef ListPartsCallback = Future<List<S3Part>> Function(
  FluppyFile file,
  ListPartsOptions options,
);

/// Signature for the signPart callback.
typedef SignPartCallback = Future<SignPartResult> Function(
  FluppyFile file,
  SignPartOptions options,
);

/// Signature for the abortMultipartUpload callback.
typedef AbortMultipartUploadCallback = Future<void> Function(
  FluppyFile file,
  AbortMultipartOptions options,
);

/// Signature for the completeMultipartUpload callback.
typedef CompleteMultipartUploadCallback = Future<CompleteMultipartResult> Function(
  FluppyFile file,
  CompleteMultipartOptions options,
);

/// Signature for the getTemporarySecurityCredentials callback.
typedef GetTemporarySecurityCredentialsCallback = Future<TemporaryCredentials> Function(CredentialsOptions options);

/// Signature for the getObjectKey callback.
///
/// Used to determine the S3 object key when using temporary credentials.
/// If not provided, defaults to [FluppyFile.name].
typedef GetObjectKeyCallback = String Function(FluppyFile file);

/// Signature for the uploadPartBytes callback.
///
/// Allows customizing how part bytes are uploaded to S3.
/// By default, Fluppy uses its internal implementation.
typedef UploadPartBytesCallback = Future<UploadPartBytesResult> Function(
  UploadPartBytesOptions options,
);

/// Default multipart threshold (100 MiB).
const int defaultMultipartThreshold = 100 * 1024 * 1024;

/// Default chunk size (5 MiB - S3 minimum).
const int defaultChunkSize = 5 * 1024 * 1024;

/// Minimum chunk size (5 MiB - S3 requirement).
const int minChunkSize = 5 * 1024 * 1024;

/// Maximum number of parts (S3 limit).
const int maxParts = 10000;

/// Configuration options for S3 uploads.
///
/// Example:
/// ```dart
/// final options = S3UploaderOptions(
///   shouldUseMultipart: (file) => file.size > 100 * 1024 * 1024,
///   getUploadParameters: (file, options) async {
///     return UploadParameters(method: 'PUT', url: presignedUrl);
///   },
///   createMultipartUpload: (file) async {
///     return CreateMultipartUploadResult(uploadId: '...', key: '...');
///   },
///   // ... other callbacks
/// );
/// ```
class S3UploaderOptions {
  /// Decide per-file whether to use multipart upload.
  ///
  /// Default: true for files > 100 MiB.
  ///
  /// Multipart uploads are beneficial for large files (100 MiB+) as they:
  /// - Improve throughput by uploading parts in parallel
  /// - Allow quick recovery from network issues (only failed parts need retry)
  ///
  /// For small files, single-part uploads have less overhead.
  final ShouldUseMultipartCallback? shouldUseMultipart;

  /// Chunk size for multipart uploads.
  ///
  /// Default: 5 MiB (S3 minimum)
  ///
  /// S3 requires a minimum of 5 MiB and supports at most 10,000 parts.
  /// If the calculated chunk size is too small, it will be increased.
  final GetChunkSizeCallback? getChunkSize;

  /// For single-part uploads: get presigned URL and headers.
  ///
  /// Called for files that don't use multipart upload.
  ///
  /// **Note**: When [getTemporarySecurityCredentials] is provided, this callback
  /// is NOT called - Fluppy signs URLs client-side instead.
  ///
  /// Returns [UploadParameters] containing:
  /// - method: 'PUT' or 'POST'
  /// - url: The presigned URL
  /// - headers: Optional headers (include Content-Type!)
  /// - fields: Optional form fields (for POST uploads)
  final GetUploadParametersCallback getUploadParameters;

  /// Initiate a multipart upload.
  ///
  /// Called at the start of a multipart upload.
  ///
  /// Returns [CreateMultipartUploadResult] containing:
  /// - uploadId: The S3 UploadId
  /// - key: The object key
  final CreateMultipartUploadCallback createMultipartUpload;

  /// List already-uploaded parts (for resume).
  ///
  /// Called when resuming a paused multipart upload to determine
  /// which parts have already been uploaded.
  ///
  /// Returns a list of [S3Part] with PartNumber, Size, and ETag.
  final ListPartsCallback listParts;

  /// Sign a single part.
  ///
  /// Called for each part in a multipart upload to get a presigned URL.
  ///
  /// **Note**: When [getTemporarySecurityCredentials] is provided, this callback
  /// is NOT called - Fluppy signs part URLs client-side instead.
  ///
  /// Returns [SignPartResult] containing:
  /// - url: The presigned URL for this part
  /// - headers: Optional headers
  final SignPartCallback signPart;

  /// Abort a multipart upload and cleanup.
  ///
  /// Called when an upload is cancelled to remove uploaded parts from S3.
  final AbortMultipartUploadCallback abortMultipartUpload;

  /// Complete a multipart upload.
  ///
  /// Called after all parts are uploaded to combine them into the final object.
  ///
  /// Returns [CompleteMultipartResult] containing:
  /// - location: The public URL to the uploaded file (optional)
  final CompleteMultipartUploadCallback completeMultipartUpload;

  /// Get temporary AWS credentials for direct uploads.
  ///
  /// Optional. When provided, Fluppy signs URLs client-side using these credentials,
  /// eliminating the need for backend signing callbacks (`getUploadParameters` and `signPart`).
  ///
  /// **Benefits**:
  /// - ~20% faster uploads (reduced request overhead)
  /// - Reduced server load (no signing requests)
  ///
  /// **Security Considerations**:
  /// - Credentials are exposed to the client (use temporary credentials only!)
  /// - Must use AWS STS (Security Token Service) to generate temporary credentials
  /// - Credentials should have minimal IAM permissions (scoped to specific bucket/operations)
  /// - Credentials should have short expiration times (typically 1 hour)
  ///
  /// **When to use**:
  /// - Use when you want faster uploads and can accept the security trade-off
  /// - Use when you already have STS infrastructure set up
  /// - Avoid if you need strict server-side control over signing
  ///
  /// **Return format**:
  /// ```dart
  /// TemporaryCredentials(
  ///   accessKeyId: 'AKIA...',
  ///   secretAccessKey: '...',
  ///   sessionToken: '...',
  ///   expiration: DateTime.now().add(Duration(hours: 1)),
  ///   bucket: 'my-bucket',
  ///   region: 'us-east-1',
  /// )
  /// ```
  ///
  /// **Note**: When this is provided, `getUploadParameters` and `signPart` callbacks
  /// are NOT called. You still need to provide `createMultipartUpload`,
  /// `completeMultipartUpload`, `listParts`, and `abortMultipartUpload` callbacks
  /// as these perform S3 API operations, not just signing.
  ///
  /// See also:
  /// - [AWS STS Documentation](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html)
  /// - [Uppy Temporary Credentials Guide](https://uppy.io/docs/aws-s3/#gettemporarysecuritycredentialsoptions)
  final GetTemporarySecurityCredentialsCallback? getTemporarySecurityCredentials;

  /// Get the S3 object key for a file.
  ///
  /// Optional. When using temporary credentials, this determines the object key
  /// for single-part uploads. If not provided, defaults to [FluppyFile.name].
  ///
  /// For multipart uploads, the key is determined by [createMultipartUpload].
  final GetObjectKeyCallback? getObjectKey;

  /// Metadata fields to include in upload.
  ///
  /// - `null`: Include all metadata
  /// - `[]`: Include no metadata
  /// - `['name', 'type']`: Include only specified fields
  final List<String>? allowedMetaFields;

  /// Maximum concurrent part uploads for a single file.
  ///
  /// Default: 3
  final int maxConcurrentParts;

  /// Retry configuration for failed requests.
  final RetryConfig retryConfig;

  /// Custom implementation for uploading part bytes.
  ///
  /// When provided, this callback is used instead of the default HTTP
  /// implementation. This allows:
  /// - Using a different HTTP client (e.g., dio for better progress tracking)
  /// - Adding custom headers or authentication
  /// - Implementing custom retry logic
  /// - Logging or metrics collection
  ///
  /// If not provided, Fluppy uses its internal implementation with the
  /// standard http package.
  final UploadPartBytesCallback? uploadPartBytes;

  /// Creates S3 uploader options.
  ///
  /// **Required callbacks** (unless using temporary credentials):
  /// - [getUploadParameters] - For single-part uploads (not called when temp creds provided)
  /// - [createMultipartUpload] - To initiate multipart uploads (always required)
  /// - [signPart] - To sign each part (not called when temp creds provided)
  /// - [completeMultipartUpload] - To finalize multipart uploads (always required)
  /// - [listParts] - To resume multipart uploads (always required)
  /// - [abortMultipartUpload] - To cancel and cleanup (always required)
  ///
  /// **When using temporary credentials**:
  /// - Provide [getTemporarySecurityCredentials] callback
  /// - [getUploadParameters] and [signPart] are optional (not called)
  /// - [createMultipartUpload], [completeMultipartUpload], [listParts], [abortMultipartUpload] still required
  const S3UploaderOptions({
    required this.getUploadParameters,
    required this.createMultipartUpload,
    required this.signPart,
    required this.completeMultipartUpload,
    required this.listParts,
    required this.abortMultipartUpload,
    this.shouldUseMultipart,
    this.getChunkSize,
    this.getTemporarySecurityCredentials,
    this.getObjectKey,
    this.allowedMetaFields,
    this.maxConcurrentParts = 3,
    this.retryConfig = RetryConfig.defaultConfig,
    this.uploadPartBytes,
  });

  /// Whether to use multipart upload for the given file.
  bool useMultipart(FluppyFile file) {
    if (shouldUseMultipart != null) {
      return shouldUseMultipart!(file);
    }
    return file.size > defaultMultipartThreshold;
  }

  /// Gets the chunk size for the given file.
  ///
  /// Ensures the chunk size is at least [minChunkSize] and doesn't
  /// result in more than [maxParts] parts.
  int chunkSize(FluppyFile file) {
    var size = getChunkSize?.call(file) ?? defaultChunkSize;

    // Ensure minimum chunk size
    if (size < minChunkSize) {
      size = minChunkSize;
    }

    // Ensure we don't exceed max parts
    final minChunkForParts = (file.size / maxParts).ceil();
    if (size < minChunkForParts) {
      size = minChunkForParts;
    }

    return size;
  }

  /// Gets the object key for the given file.
  ///
  /// Uses [getObjectKey] callback if provided, otherwise defaults to [FluppyFile.name].
  String objectKey(FluppyFile file) {
    return getObjectKey?.call(file) ?? file.name;
  }
}

/// Options for retry behavior.
///
/// Supports two modes:
/// 1. **Exponential backoff** (default): Delays increase exponentially
/// 2. **Explicit delays**: Array of retry delays
///
/// Example with exponential backoff:
/// ```dart
/// RetryOptions(
///   maxRetries: 3,
///   initialDelay: Duration(seconds: 1),
///   maxDelay: Duration(seconds: 30),
/// )
/// ```
///
/// Example with explicit delays:
/// ```dart
/// RetryOptions.withDelays([0, 1000, 3000, 5000]) // milliseconds
/// ```
class RetryConfig {
  /// Maximum number of retries per part.
  final int maxRetries;

  /// Initial delay before first retry.
  final Duration initialDelay;

  /// Maximum delay between retries.
  final Duration maxDelay;

  /// Whether to use exponential backoff.
  final bool exponentialBackoff;

  /// Explicit retry delays in milliseconds.
  ///
  /// When provided, these delays are used instead of exponential backoff.
  /// Example: `[0, 1000, 3000, 5000]` means:
  /// - First retry: immediate (0ms)
  /// - Second retry: after 1 second
  /// - Third retry: after 3 seconds
  /// - Fourth retry: after 5 seconds
  final List<int>? retryDelays;

  const RetryConfig({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.exponentialBackoff = true,
    this.retryDelays,
  });

  /// Creates retry options with explicit delays.
  ///
  /// [delays] is a list of delays in milliseconds.
  /// Example: `[0, 1000, 3000, 5000]`
  factory RetryConfig.withDelays(List<int> delays) {
    return RetryConfig(
      maxRetries: delays.length,
      retryDelays: delays,
      exponentialBackoff: false,
    );
  }

  static const defaultConfig = RetryConfig();

  /// Calculates the delay for a given attempt (0-indexed).
  Duration getDelay(int attempt) {
    // First attempt (attempt 0) has no delay
    if (attempt <= 0) return Duration.zero;

    // Use explicit delays if provided (attempt 1 uses index 0, etc.)
    if (retryDelays != null && retryDelays!.isNotEmpty) {
      final index = attempt - 1;
      if (index >= retryDelays!.length) {
        return Duration(milliseconds: retryDelays!.last);
      }
      return Duration(milliseconds: retryDelays![index]);
    }

    // Use exponential backoff (attempt 1 = initialDelay * 2^0, attempt 2 = initialDelay * 2^1, etc.)
    if (!exponentialBackoff) {
      return initialDelay;
    }

    var delayMs = initialDelay.inMilliseconds * (1 << (attempt - 1));
    if (delayMs > maxDelay.inMilliseconds) {
      delayMs = maxDelay.inMilliseconds;
    }

    return Duration(milliseconds: delayMs);
  }
}

/// Utility for filtering metadata fields.
class MetadataUtils {
  /// Filters metadata to only include allowed fields.
  ///
  /// Parameters:
  /// - [meta]: The full metadata map
  /// - [allowedMetaFields]: Which fields to include:
  ///   - `null`: Include all fields
  ///   - `[]`: Include no fields (empty result)
  ///   - `['name', 'type']`: Include only specified fields
  /// - [querify]: If true, prefixes keys with `metadata[...]` for query params
  ///
  /// Example:
  /// ```dart
  /// final meta = {'name': 'file.txt', 'type': 'text/plain', 'custom': 'value'};
  ///
  /// // Include all
  /// getAllowedMetadata(meta: meta, allowedMetaFields: null);
  /// // => {'name': 'file.txt', 'type': 'text/plain', 'custom': 'value'}
  ///
  /// // Include specific fields
  /// getAllowedMetadata(meta: meta, allowedMetaFields: ['name', 'type']);
  /// // => {'name': 'file.txt', 'type': 'text/plain'}
  ///
  /// // Querify for URL params
  /// getAllowedMetadata(meta: meta, allowedMetaFields: ['name'], querify: true);
  /// // => {'metadata[name]': 'file.txt'}
  /// ```
  static Map<String, String> getAllowedMetadata({
    required Map<String, dynamic> meta,
    List<String>? allowedMetaFields,
    bool querify = false,
  }) {
    // Determine which fields to include
    final fieldsToInclude = allowedMetaFields ?? meta.keys.toList();

    // Build result map
    final result = <String, String>{};
    for (final key in fieldsToInclude) {
      final value = meta[key];
      if (value != null) {
        final resultKey = querify ? 'metadata[$key]' : key;
        result[resultKey] = value.toString();
      }
    }

    return result;
  }

  /// Convenience method to check if a meta field is allowed.
  static bool isFieldAllowed(String field, List<String>? allowedMetaFields) {
    if (allowedMetaFields == null) return true;
    return allowedMetaFields.contains(field);
  }
}
