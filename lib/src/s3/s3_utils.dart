import 's3_types.dart';

/// Helper utilities for S3 URL handling.
///
/// These utilities are provided for users who want to construct or decode
/// S3 URLs. Fluppy's S3 uploader returns raw URLs by default (matching Uppy.js),
/// but these helpers can be used in callbacks or event handlers.
///
/// Example usage in completeMultipartUpload callback:
/// ```dart
/// completeMultipartUpload: (file, options) async {
///   final response = await backend.complete(...);
///
///   // Use helper to construct URL if backend doesn't return one
///   final location = response.url ?? S3Utils.constructUrl(
///     bucket: 'my-bucket',
///     region: 'us-east-1',
///     key: options.key,
///   );
///
///   return CompleteMultipartResult(
///     location: S3Utils.decodeUrlPath(location), // Optional: decode for display
///     body: {...},
///   );
/// },
/// ```
class S3Utils {
  S3Utils._(); // Prevent instantiation

  /// Constructs an S3 URL from bucket, region, and key.
  ///
  /// Returns a URL in the format:
  /// `https://{bucket}.s3.{region}.amazonaws.com/{key}`
  ///
  /// The key is properly URL-encoded for S3 compatibility.
  ///
  /// Example:
  /// ```dart
  /// final url = S3Utils.constructUrl(
  ///   bucket: 'my-bucket',
  ///   region: 'us-east-1',
  ///   key: 'uploads/my file (1).jpg',
  /// );
  /// // Returns: https://my-bucket.s3.us-east-1.amazonaws.com/uploads/my%20file%20%281%29.jpg
  /// ```
  static String constructUrl({
    required String bucket,
    required String region,
    required String key,
  }) {
    // Encode path segments properly for S3
    final pathSegments = key.split('/').map((segment) {
      var encoded = Uri.encodeComponent(segment);
      // Encode parentheses to match S3/AWS signature encoding
      encoded = encoded.replaceAll('(', '%28').replaceAll(')', '%29');
      return encoded;
    }).join('/');

    return 'https://$bucket.s3.$region.amazonaws.com/$pathSegments';
  }

  /// Constructs an S3 URL from [TemporaryCredentials] and a key.
  ///
  /// Convenience method that extracts bucket and region from credentials.
  ///
  /// Example:
  /// ```dart
  /// final url = S3Utils.constructUrlFromCredentials(
  ///   credentials: tempCreds,
  ///   key: 'uploads/file.jpg',
  /// );
  /// ```
  static String constructUrlFromCredentials({
    required TemporaryCredentials credentials,
    required String key,
  }) {
    return constructUrl(
      bucket: credentials.bucket,
      region: credentials.region,
      key: key,
    );
  }

  /// Decodes URL-encoded path segments for cleaner display.
  ///
  /// Converts encoded characters like `%2F` back to `/`, `%20` to space, etc.
  /// Useful for displaying URLs in a user-friendly format.
  ///
  /// Example:
  /// ```dart
  /// final decoded = S3Utils.decodeUrlPath(
  ///   'https://bucket.s3.us-east-1.amazonaws.com/uploads%2Fmy%20file.jpg'
  /// );
  /// // Returns: https://bucket.s3.us-east-1.amazonaws.com/uploads/my file.jpg
  /// ```
  ///
  /// Returns the original URL if decoding fails or if the input is not a valid URL.
  static String decodeUrlPath(String url) {
    try {
      final uri = Uri.parse(url);
      // Check if it's a valid absolute URL with a scheme
      if (uri.scheme.isEmpty) {
        return url;
      }
      final decodedPath = Uri.decodeComponent(uri.path);
      // Preserve scheme, authority (host:port), use decoded path
      return '${uri.scheme}://${uri.authority}$decodedPath';
    } catch (_) {
      return url;
    }
  }

  /// Extracts the ETag value, handling both quoted and unquoted formats.
  ///
  /// S3 returns ETags in quotes (e.g., `"abc123"`), but some systems
  /// strip the quotes. This helper normalizes the format by adding quotes.
  ///
  /// Example:
  /// ```dart
  /// S3Utils.normalizeETag('"abc123"');  // Returns: "abc123"
  /// S3Utils.normalizeETag('abc123');    // Returns: "abc123"
  /// ```
  static String normalizeETag(String eTag) {
    if (eTag.startsWith('"') && eTag.endsWith('"')) {
      return eTag;
    }
    return '"$eTag"';
  }

  /// Strips quotes from an ETag value.
  ///
  /// Example:
  /// ```dart
  /// S3Utils.stripETagQuotes('"abc123"');  // Returns: abc123
  /// S3Utils.stripETagQuotes('abc123');    // Returns: abc123
  /// ```
  static String stripETagQuotes(String eTag) {
    if (eTag.startsWith('"') && eTag.endsWith('"')) {
      return eTag.substring(1, eTag.length - 1);
    }
    return eTag;
  }
}
