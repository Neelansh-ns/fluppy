import '../core/fluppy_file.dart';
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
/// Mirrors the API of [@uppy/aws-s3](https://uppy.io/docs/aws-s3/).
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

  /// Maximum number of concurrent file uploads.
  ///
  /// Default: 6
  ///
  /// Note: This limits concurrent files, not concurrent requests.
  /// A multipart upload may use many requests per file.
  final int limit;

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
  /// Optional. When provided, reduces request overhead as users get a single
  /// token for bucket operations instead of signing each request.
  ///
  /// This is a security tradeoff - see AWS documentation.
  final GetTemporarySecurityCredentialsCallback? getTemporarySecurityCredentials;

  /// Metadata fields to include in upload.
  ///
  /// - null: Include all metadata
  /// - []: Include no metadata
  /// - ['name', 'type']: Include only specified fields
  final List<String>? allowedMetaFields;

  /// Maximum concurrent part uploads for a single file.
  ///
  /// Default: 3
  final int maxConcurrentParts;

  /// Retry configuration for failed requests.
  final RetryOptions retryOptions;

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
  /// Required callbacks:
  /// - [getUploadParameters] - For single-part uploads
  /// - [createMultipartUpload] - To initiate multipart uploads
  /// - [signPart] - To sign each part
  /// - [completeMultipartUpload] - To finalize multipart uploads
  /// - [listParts] - To resume multipart uploads
  /// - [abortMultipartUpload] - To cancel and cleanup
  const S3UploaderOptions({
    required this.getUploadParameters,
    required this.createMultipartUpload,
    required this.signPart,
    required this.completeMultipartUpload,
    required this.listParts,
    required this.abortMultipartUpload,
    this.shouldUseMultipart,
    this.limit = 6,
    this.getChunkSize,
    this.getTemporarySecurityCredentials,
    this.allowedMetaFields,
    this.maxConcurrentParts = 3,
    this.retryOptions = const RetryOptions(),
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
}

/// Options for retry behavior.
///
/// Supports two modes:
/// 1. **Exponential backoff** (default): Delays increase exponentially
/// 2. **Explicit delays**: Uppy-style array of retry delays
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
/// Example with Uppy-style delays:
/// ```dart
/// RetryOptions.withDelays([0, 1000, 3000, 5000]) // milliseconds
/// ```
class RetryOptions {
  /// Maximum number of retries per part.
  final int maxRetries;

  /// Initial delay before first retry.
  final Duration initialDelay;

  /// Maximum delay between retries.
  final Duration maxDelay;

  /// Whether to use exponential backoff.
  final bool exponentialBackoff;

  /// Explicit retry delays in milliseconds (Uppy-style).
  ///
  /// When provided, these delays are used instead of exponential backoff.
  /// Example: `[0, 1000, 3000, 5000]` means:
  /// - First retry: immediate (0ms)
  /// - Second retry: after 1 second
  /// - Third retry: after 3 seconds
  /// - Fourth retry: after 5 seconds
  final List<int>? retryDelays;

  const RetryOptions({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.exponentialBackoff = true,
    this.retryDelays,
  });

  /// Creates retry options with explicit delays (Uppy-style).
  ///
  /// [delays] is a list of delays in milliseconds.
  /// Example: `[0, 1000, 3000, 5000]`
  factory RetryOptions.withDelays(List<int> delays) {
    return RetryOptions(
      maxRetries: delays.length,
      retryDelays: delays,
      exponentialBackoff: false,
    );
  }

  /// Default Uppy-style retry delays: [0, 1000, 3000, 5000].
  static const uppyDefaults = RetryOptions(
    maxRetries: 4,
    retryDelays: [0, 1000, 3000, 5000],
    exponentialBackoff: false,
  );

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
///
/// Mirrors Uppy's `getAllowedMetaFields` behavior.
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
