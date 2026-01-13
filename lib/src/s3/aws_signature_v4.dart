import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 's3_types.dart';

/// AWS Signature Version 4 implementation for creating presigned URLs.
///
/// This allows generating presigned URLs client-side using temporary
/// credentials, reducing server round-trips for signing each part.
///
/// Example:
/// ```dart
/// final signer = AwsSignatureV4(
///   accessKeyId: credentials.accessKeyId,
///   secretAccessKey: credentials.secretAccessKey,
///   sessionToken: credentials.sessionToken,
///   region: credentials.region,
///   bucket: credentials.bucket,
/// );
///
/// final signedUrl = signer.createPresignedUrl(
///   key: 'my-file.mp4',
///   expires: 3600,
/// );
/// ```
class AwsSignatureV4 {
  /// AWS Access Key ID.
  final String accessKeyId;

  /// AWS Secret Access Key.
  final String secretAccessKey;

  /// AWS Session Token (for temporary credentials).
  final String? sessionToken;

  /// AWS region (e.g., 'us-east-1').
  final String region;

  /// S3 bucket name.
  final String bucket;

  /// Service name (always 's3' for S3).
  static const String service = 's3';

  /// Creates an AWS Signature V4 signer.
  const AwsSignatureV4({
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken,
    required this.region,
    required this.bucket,
  });

  /// Creates a signer from temporary credentials.
  factory AwsSignatureV4.fromCredentials(TemporaryCredentials credentials) {
    return AwsSignatureV4(
      accessKeyId: credentials.accessKeyId,
      secretAccessKey: credentials.secretAccessKey,
      sessionToken: credentials.sessionToken,
      region: credentials.region,
      bucket: credentials.bucket,
    );
  }

  /// Creates a presigned URL for uploading a file or part.
  ///
  /// Parameters:
  /// - [key]: The S3 object key
  /// - [expires]: URL expiration time in seconds (default: 3600, max: 604800)
  /// - [uploadId]: For multipart uploads, the upload ID
  /// - [partNumber]: For multipart uploads, the part number
  /// - [contentType]: Optional content type header to sign
  /// - [method]: HTTP method (default: 'PUT')
  ///
  /// Returns an [UploadParameters] containing the presigned URL and headers.
  UploadParameters createPresignedUrl({
    required String key,
    int expires = 3600,
    String? uploadId,
    int? partNumber,
    String? contentType,
    String method = 'PUT',
  }) {
    final now = DateTime.now().toUtc();
    final dateStamp = _formatDateStamp(now);
    final amzDate = _formatAmzDate(now);

    // Build canonical URI
    final canonicalUri = '/${Uri.encodeComponent(key)}';

    // Build query parameters
    final queryParams = <String, String>{
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': '$accessKeyId/$dateStamp/$region/$service/aws4_request',
      'X-Amz-Date': amzDate,
      'X-Amz-Expires': expires.toString(),
      'X-Amz-SignedHeaders': 'host',
    };

    if (sessionToken != null) {
      queryParams['X-Amz-Security-Token'] = sessionToken!;
    }

    if (uploadId != null) {
      queryParams['uploadId'] = uploadId;
    }

    if (partNumber != null) {
      queryParams['partNumber'] = partNumber.toString();
    }

    // Build canonical query string (sorted)
    final sortedKeys = queryParams.keys.toList()..sort();
    final canonicalQueryString =
        sortedKeys.map((k) => '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(queryParams[k]!)}').join('&');

    // Build canonical headers
    final host = '$bucket.s3.$region.amazonaws.com';
    final canonicalHeaders = 'host:$host\n';
    const signedHeaders = 'host';

    // Build canonical request
    final canonicalRequest = [
      method,
      canonicalUri,
      canonicalQueryString,
      canonicalHeaders,
      signedHeaders,
      'UNSIGNED-PAYLOAD', // For presigned URLs, payload is unsigned
    ].join('\n');

    // Calculate string to sign
    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = ['AWS4-HMAC-SHA256', amzDate, credentialScope, _sha256Hash(canonicalRequest)].join('\n');

    // Calculate signature
    final signingKey = _getSignatureKey(dateStamp);
    final signature = _hmacSha256Hex(signingKey, stringToSign);

    // Build final URL
    final signedUrl = 'https://$host$canonicalUri?$canonicalQueryString&X-Amz-Signature=$signature';

    // Build headers
    final headers = <String, String>{};
    if (contentType != null) {
      headers['Content-Type'] = contentType;
    }

    return UploadParameters(
      method: method,
      url: signedUrl,
      headers: headers.isEmpty ? null : headers,
      expires: expires,
    );
  }

  /// Creates a presigned URL for a multipart upload part.
  SignPartResult createPresignedPartUrl({
    required String key,
    required String uploadId,
    required int partNumber,
    int expires = 3600,
  }) {
    final params = createPresignedUrl(key: key, uploadId: uploadId, partNumber: partNumber, expires: expires);

    return SignPartResult(url: params.url, headers: params.headers, expires: expires);
  }

  // ============================================
  // Private Helpers
  // ============================================

  /// Formats a DateTime as YYYYMMDD.
  String _formatDateStamp(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }

  /// Formats a DateTime as YYYYMMDD'T'HHMMSS'Z'.
  String _formatAmzDate(DateTime date) {
    return '${_formatDateStamp(date)}T'
        '${date.hour.toString().padLeft(2, '0')}'
        '${date.minute.toString().padLeft(2, '0')}'
        '${date.second.toString().padLeft(2, '0')}Z';
  }

  /// Computes SHA-256 hash and returns hex string.
  String _sha256Hash(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Computes HMAC-SHA256 and returns bytes.
  Uint8List _hmacSha256(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(utf8.encode(data));
    return Uint8List.fromList(digest.bytes);
  }

  /// Computes HMAC-SHA256 and returns hex string.
  String _hmacSha256Hex(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(utf8.encode(data));
    return digest.toString();
  }

  /// Derives the signing key for AWS Signature V4.
  Uint8List _getSignatureKey(String dateStamp) {
    final kSecret = utf8.encode('AWS4$secretAccessKey');
    final kDate = _hmacSha256(kSecret, dateStamp);
    final kRegion = _hmacSha256(kDate, region);
    final kService = _hmacSha256(kRegion, service);
    final kSigning = _hmacSha256(kService, 'aws4_request');
    return kSigning;
  }
}

/// Extension to create signed URLs from TemporaryCredentials.
extension TemporaryCredentialsSigningExtension on TemporaryCredentials {
  /// Creates a signer from these credentials.
  AwsSignatureV4 get signer => AwsSignatureV4.fromCredentials(this);

  /// Creates a presigned URL for uploading.
  UploadParameters createPresignedUrl({
    required String key,
    int expires = 3600,
    String? uploadId,
    int? partNumber,
    String? contentType,
  }) {
    return signer.createPresignedUrl(
      key: key,
      expires: expires,
      uploadId: uploadId,
      partNumber: partNumber,
      contentType: contentType,
    );
  }

  /// Creates a presigned URL for a multipart upload part.
  SignPartResult createPresignedPartUrl({
    required String key,
    required String uploadId,
    required int partNumber,
    int expires = 3600,
  }) {
    return signer.createPresignedPartUrl(key: key, uploadId: uploadId, partNumber: partNumber, expires: expires);
  }
}
