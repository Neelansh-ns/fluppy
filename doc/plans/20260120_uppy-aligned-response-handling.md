# Uppy-Aligned Response Handling Implementation Plan

| Field | Value |
|-------|-------|
| **Created** | 2026-01-20 |
| **Last Updated** | 2026-01-20 |
| **Uppy Reference** | [AWS S3 Plugin - uploadPartBytes](https://github.com/transloadit/uppy/blob/main/packages/%40uppy/aws-s3/src/index.ts#L670-L797) |
| **Status** | Draft |

## Overview

Align Fluppy's S3 upload response handling with Uppy.js by:
1. Returning raw response headers/location without automatic URL construction or decoding
2. Exposing `S3Utils` helper class for users who want URL construction/decoding functionality

**Problem Statement**: Fluppy currently does "magic" that Uppy doesn't:
- Constructs S3 URLs from temporary credentials when location is missing
- Decodes URL paths for "cleaner display"

This divergence reduces flexibility and makes behavior less predictable for users familiar with Uppy.

**Note on ETag**: Uppy adds capitalized `ETag` for backward compatibility with their previous API. Fluppy has always used lowercase `eTag`, so we'll continue using lowercase only - no need to add capitalized `ETag` since it was never part of our API.

## Current State Analysis

### What Uppy Does

**Single-part uploads** ([index.ts:729-784](https://github.com/transloadit/uppy/blob/main/packages/%40uppy/aws-s3/src/index.ts#L729-L784)):
```typescript
xhr.addEventListener('load', () => {
  // Parse all headers into a map
  const headersMap: Record<string, string> = { __proto__: null }
  for (const line of arr) {
    const parts = line.split(': ')
    const header = parts.shift()!
    const value = parts.join(': ')
    headersMap[header] = value
  }
  const { etag, location } = headersMap

  // Warning if location missing (CORS issue)
  if (method.toUpperCase() === 'POST' && location == null) {
    console.error('@uppy/aws-s3: Could not read the Location header...')
  }

  onComplete?.(etag)
  resolve({
    ...headersMap,           // ALL headers (lowercase from browser)
    ETag: etag,              // keep capitalised ETag for backwards compatibility
  })
})
```

**Multipart uploads** ([index.ts:841-858](https://github.com/transloadit/uppy/blob/main/packages/%40uppy/aws-s3/src/index.ts#L841-L858)):
```typescript
const onSuccess = (result: B) => {
  const uploadResp = {
    body: { ...result },     // Raw callback result spread
    status: 200,
    uploadURL: result.location as string,  // Raw location from callback
  }
  this.uppy.emit('upload-success', this.#getFile(file), uploadResp)
}
```

**Key Uppy patterns:**
- Returns raw headers with no URL construction/decoding
- `completeMultipartUpload` return type: `MaybePromise<{ location?: string }>`

**Note**: Uppy includes both `etag` and `ETag` for their backward compatibility. Fluppy has always used lowercase `eTag`, so we'll stick with that.

### What Fluppy Currently Does (Issues)

**Single-part uploads** ([s3_uploader.dart:365-410](lib/src/s3/s3_uploader.dart#L365-L410)):
```dart
// Issue 1: Constructs URL from temp credentials
if (tempCredentials != null && objectKey != null) {
  location = 'https://${tempCredentials.bucket}.s3.${tempCredentials.region}.amazonaws.com/$pathSegments';
}

// Issue 2: Decodes URL paths
final decodedPath = Uri.decodeComponent(uri.path);
location = '${uri.scheme}://${uri.authority}$decodedPath';

// Issue 3: Only lowercase eTag
final Map<String, dynamic> responseBody = {
  if (eTag != null) 'eTag': eTag,  // Missing capitalized ETag
};
```

**Multipart uploads** ([multipart_upload_controller.dart:548-621](lib/src/s3/multipart_upload_controller.dart#L548-L621)):
```dart
// Issue 1: Constructs URL from temp credentials if not provided
if (location == null && getTemporaryCredentials != null) {
  location = 'https://${credentials.bucket}.s3...';
}

// Issue 2: Decodes URL paths
final decodedPath = Uri.decodeComponent(uri.path);

// Issue 3: Only lowercase eTag in body
if (result.eTag != null) 'eTag': result.eTag,
```

### Comparison Summary

| Aspect | Uppy.js | Current Fluppy | Target Fluppy |
|--------|---------|----------------|---------------|
| Single-part location | Raw from headers | Constructed/decoded | Raw from headers |
| Multipart location | Raw from callback | Callback OR constructed | Raw from callback |
| URL decoding | None | Yes | None (helper available) |
| Fallback construction | None | Yes | None (helper available) |

## Desired End State

After implementation:

1. **Raw responses**: Location and headers passed through without modification
2. **Helper utilities**: `S3Utils` class for users who want URL construction/decoding
3. **Uppy alignment**: Response structure matches Uppy's behavior

**Success Criteria:**
- [ ] Single-part uploads return raw `location` from headers (no construction)
- [ ] Multipart uploads return raw `location` from callback (no fallback)
- [ ] No automatic URL decoding anywhere
- [ ] `S3Utils` helper class exposed for URL construction/decoding
- [ ] All tests updated and pass
- [ ] Example demonstrates helper usage for users who want old behavior

## Uppy Alignment

### API Mapping

| Uppy Response Field | Fluppy Response Field | Notes |
|---------------------|----------------------|-------|
| `headersMap.etag` | `body['eTag']` | Lowercase (Fluppy convention) |
| `headersMap.location` | `location` | Raw, no modification |
| `result.location` | `location` (multipart) | Raw from callback |

### Type Mapping

| Uppy Type | Fluppy Type | Notes |
|-----------|-------------|-------|
| `UploadPartBytesResult.ETag` | `UploadPartBytesResult.eTag` | Lowercase (Fluppy convention) |
| `AwsS3Part.ETag` | `S3Part.eTag` | Lowercase internally |
| `{ location?: string }` | `CompleteMultipartResult` | Callback return type |

## What We're NOT Doing

1. **Not adding capitalized `ETag`** - Uppy does this for their backward compat, but Fluppy never used it
2. **Not changing internal field names** - `S3Part.eTag` stays lowercase internally
3. **Not removing `CompleteMultipartResult.body`** - Keep the flexible body field from previous plan
4. **Not breaking `S3Part.fromJson/toJson`** - These already handle `ETag` capitalization for S3 API

---

## Phase 1: Simplify Single-Part Upload Response

### Overview
Remove automatic URL construction and decoding from single-part uploads. Return raw location from headers.

### Files to Modify

#### 1. `lib/src/s3/s3_uploader.dart`

**Changes**: Remove URL construction and decoding logic

**Current code** (lines 365-399):
```dart
// Extract ETag and location
final eTag = response.headers['etag'];
// For temp creds, construct location from bucket/region/key
String location;
if (tempCredentials != null && objectKey != null) {
  // Construct URL with proper path encoding...
  final pathSegments = objectKey.split('/').map((s) {
    var encoded = Uri.encodeComponent(s);
    encoded = encoded.replaceAll('(', '%28').replaceAll(')', '%29');
    return encoded;
  }).join('/');
  final encodedUrl = 'https://${tempCredentials.bucket}.s3.${tempCredentials.region}.amazonaws.com/$pathSegments';
  // Decode the path for cleaner display...
  try {
    final uri = Uri.parse(encodedUrl);
    final decodedPath = Uri.decodeComponent(uri.path);
    location = '${uri.scheme}://${uri.authority}$decodedPath';
  } catch (_) {
    location = encodedUrl;
  }
} else {
  // Decode URL path for cleaner display...
  final rawLocation = response.headers['location'] ?? params.url.split('?').first;
  try {
    final uri = Uri.parse(rawLocation);
    final decodedPath = Uri.decodeComponent(uri.path);
    location = '${uri.scheme}://${uri.authority}$decodedPath';
  } catch (_) {
    location = rawLocation;
  }
}
```

**New code**:
```dart
// Extract ETag and location - return raw values like Uppy
final eTag = response.headers['etag'];

// Use raw location from headers, or presigned URL base as fallback
// NO construction from temp credentials, NO URL decoding
// Users can use S3Utils helpers if they want that functionality
final location = response.headers['location'] ?? params.url.split('?').first;

// Log warning if location missing (like Uppy does for POST)
if (location.isEmpty) {
  // Note: This is informational, not an error
  // CORS must be configured to expose Location header
}
```

**Why**: Matches Uppy's behavior of returning raw headers without manipulation.

### Success Criteria
- [ ] No URL construction from temp credentials
- [ ] No URL path decoding
- [ ] Raw location from headers returned
- [ ] Fallback to presigned URL base (without query params) if no header

---

## Phase 2: Simplify Multipart Upload Response

### Overview
Remove automatic URL construction and decoding from multipart uploads. Return raw location from callback.

### Files to Modify

#### 1. `lib/src/s3/multipart_upload_controller.dart`

**Changes**: Remove URL construction fallback and decoding

**Current code** (lines 568-606):
```dart
// Decode location URL for cleaner display (backend may return encoded paths)
String? location = result.location;
if (location != null) {
  try {
    final uri = Uri.parse(location);
    final decodedPath = Uri.decodeComponent(uri.path);
    location = '${uri.scheme}://${uri.authority}$decodedPath';
  } catch (_) {
    // If parsing fails, use original location
  }
} else if (getTemporaryCredentials != null && file.s3Multipart.key != null) {
  // Construct location from temp credentials if not provided by backend
  try {
    final credentials = await getTemporaryCredentials!();
    if (credentials != null) {
      final key = file.s3Multipart.key!;
      final pathSegments = key.split('/').map((s) {
        var encoded = Uri.encodeComponent(s);
        encoded = encoded.replaceAll('(', '%28').replaceAll(')', '%29');
        return encoded;
      }).join('/');
      final encodedUrl = 'https://${credentials.bucket}.s3.${credentials.region}.amazonaws.com/$pathSegments';
      try {
        final uri = Uri.parse(encodedUrl);
        final decodedPath = Uri.decodeComponent(uri.path);
        location = '${uri.scheme}://${uri.authority}$decodedPath';
      } catch (_) {
        location = encodedUrl;
      }
    }
  } catch (_) {
    // If getting credentials fails, location remains null
  }
}
```

**New code**:
```dart
// Use raw location from callback - NO construction, NO decoding
// Matches Uppy: uploadURL: result.location as string
// Users can use S3Utils helpers if they want URL construction/decoding
final location = result.location;
```

**Why**: Matches Uppy's behavior of passing through raw callback result.

### Success Criteria
- [ ] No URL construction from temp credentials
- [ ] No URL path decoding
- [ ] Raw location from callback returned (can be null)

---

## Phase 3: Create S3Utils Helper Class

### Overview
Expose helper utilities for users who want URL construction and decoding functionality.

### New Files to Create

#### 1. `lib/src/s3/s3_utils.dart`

**Purpose**: Provide opt-in helper functions for URL manipulation

```dart
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
  /// Returns the original URL if decoding fails.
  static String decodeUrlPath(String url) {
    try {
      final uri = Uri.parse(url);
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
  /// strip the quotes. This helper normalizes the format.
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
```

#### 2. Update `lib/fluppy.dart` exports

**Changes**: Export the new S3Utils class

```dart
// Add to existing exports
export 'src/s3/s3_utils.dart' show S3Utils;
```

### Success Criteria
- [ ] `S3Utils.constructUrl()` creates proper S3 URLs
- [ ] `S3Utils.constructUrlFromCredentials()` works with temp creds
- [ ] `S3Utils.decodeUrlPath()` properly decodes encoded paths
- [ ] `S3Utils.normalizeETag()` and `stripETagQuotes()` handle both formats
- [ ] Class exported from main library

---

## Phase 4: Update Tests and Examples

### Overview
Update tests to verify new behavior and examples to demonstrate helper usage.

### Tests to Add/Modify

#### 1. `test/s3_utils_test.dart` (new file)

```dart
import 'package:fluppy/fluppy.dart';
import 'package:test/test.dart';

void main() {
  group('S3Utils', () {
    group('constructUrl', () {
      test('constructs basic URL', () {
        final url = S3Utils.constructUrl(
          bucket: 'my-bucket',
          region: 'us-east-1',
          key: 'file.jpg',
        );
        expect(url, 'https://my-bucket.s3.us-east-1.amazonaws.com/file.jpg');
      });

      test('encodes spaces in key', () {
        final url = S3Utils.constructUrl(
          bucket: 'my-bucket',
          region: 'us-east-1',
          key: 'my file.jpg',
        );
        expect(url, 'https://my-bucket.s3.us-east-1.amazonaws.com/my%20file.jpg');
      });

      test('encodes special characters', () {
        final url = S3Utils.constructUrl(
          bucket: 'my-bucket',
          region: 'us-east-1',
          key: 'file (1).jpg',
        );
        expect(url, 'https://my-bucket.s3.us-east-1.amazonaws.com/file%20%281%29.jpg');
      });

      test('handles nested paths', () {
        final url = S3Utils.constructUrl(
          bucket: 'my-bucket',
          region: 'us-east-1',
          key: 'uploads/2026/01/file.jpg',
        );
        expect(url, 'https://my-bucket.s3.us-east-1.amazonaws.com/uploads/2026/01/file.jpg');
      });
    });

    group('decodeUrlPath', () {
      test('decodes encoded path', () {
        final decoded = S3Utils.decodeUrlPath(
          'https://bucket.s3.us-east-1.amazonaws.com/uploads%2Ffile.jpg',
        );
        expect(decoded, 'https://bucket.s3.us-east-1.amazonaws.com/uploads/file.jpg');
      });

      test('decodes spaces', () {
        final decoded = S3Utils.decodeUrlPath(
          'https://bucket.s3.us-east-1.amazonaws.com/my%20file.jpg',
        );
        expect(decoded, 'https://bucket.s3.us-east-1.amazonaws.com/my file.jpg');
      });

      test('returns original on invalid URL', () {
        final decoded = S3Utils.decodeUrlPath('not a url');
        expect(decoded, 'not a url');
      });

      test('preserves already decoded URL', () {
        final decoded = S3Utils.decodeUrlPath(
          'https://bucket.s3.us-east-1.amazonaws.com/file.jpg',
        );
        expect(decoded, 'https://bucket.s3.us-east-1.amazonaws.com/file.jpg');
      });
    });

    group('normalizeETag', () {
      test('adds quotes to unquoted ETag', () {
        expect(S3Utils.normalizeETag('abc123'), '"abc123"');
      });

      test('preserves already quoted ETag', () {
        expect(S3Utils.normalizeETag('"abc123"'), '"abc123"');
      });
    });

    group('stripETagQuotes', () {
      test('strips quotes from ETag', () {
        expect(S3Utils.stripETagQuotes('"abc123"'), 'abc123');
      });

      test('handles unquoted ETag', () {
        expect(S3Utils.stripETagQuotes('abc123'), 'abc123');
      });
    });
  });
}
```

#### 2. Update `example/example.dart`

Add example showing S3Utils usage:

```dart
// In the completeMultipartUpload callback, show how to use helpers:
completeMultipartUpload: (file, options) async {
  final response = await myBackend.completeUpload(...);

  // Option 1: Use raw location from backend (recommended)
  // return CompleteMultipartResult(
  //   location: response.url,
  //   body: {...},
  // );

  // Option 2: Construct URL if backend doesn't return one
  final location = response.url ?? S3Utils.constructUrl(
    bucket: 'your-bucket',
    region: 'us-east-1',
    key: options.key,
  );

  // Option 3: Decode URL for cleaner display
  return CompleteMultipartResult(
    location: S3Utils.decodeUrlPath(location),
    body: {
      'mediaId': response.mediaId,
    },
  );
},

// In the event handler:
case UploadComplete(:final file, :final response):
  print('✅ Complete: ${file.name}');
  print('   Location: ${response?.location}');

  // Access eTag from body
  final eTag = response?.body?['eTag'];
  if (eTag != null) print('   ETag: $eTag');
```

### Success Criteria
- [ ] All new S3Utils tests pass
- [ ] Example demonstrates helper usage
- [ ] All existing tests still pass
- [ ] `dart test` passes
- [ ] `dart analyze` passes

---

## Testing Strategy

### Unit Tests
- `S3Utils.constructUrl()` with various key formats
- `S3Utils.decodeUrlPath()` with encoded and plain URLs
- `S3Utils.normalizeETag()` and `stripETagQuotes()` edge cases

### Integration Tests
- Single-part upload returns raw location from headers
- Multipart upload returns raw location from callback

### Manual Testing
1. Upload file with temp credentials - verify raw URL returned (no construction)
2. Upload file and check response body has both ETag cases
3. Use `S3Utils.constructUrl()` in callback - verify URL is correct
4. Use `S3Utils.decodeUrlPath()` on encoded URL - verify decoding works

---

## Migration Guide

### Breaking Change: Location No Longer Auto-Constructed

**Before** (Fluppy auto-constructed URLs):
```dart
// Location was automatically constructed from temp credentials
// even if backend didn't return it
case UploadComplete(:final response):
  // location was always available
  print(response?.location);
```

**After** (Raw location like Uppy):
```dart
// Location comes raw from backend - may be null if not returned
case UploadComplete(:final response):
  // Check for null, or use S3Utils to construct
  final location = response?.location ?? S3Utils.constructUrl(
    bucket: 'my-bucket',
    region: 'us-east-1',
    key: response?.body?['key'] as String,
  );
  print(location);
```

### Breaking Change: URL Paths No Longer Auto-Decoded

**Before**:
```dart
// URLs were automatically decoded for "cleaner display"
// https://bucket.s3.region.amazonaws.com/uploads/my file.jpg
```

**After**:
```dart
// URLs returned raw (may be encoded)
// https://bucket.s3.region.amazonaws.com/uploads/my%20file.jpg

// Use helper if you want decoded display
final decoded = S3Utils.decodeUrlPath(response?.location ?? '');
```

---

## References

- **Uppy uploadPartBytes**: [index.ts:670-797](https://github.com/transloadit/uppy/blob/main/packages/%40uppy/aws-s3/src/index.ts#L670-L797)
- **Uppy onSuccess**: [index.ts:841-858](https://github.com/transloadit/uppy/blob/main/packages/%40uppy/aws-s3/src/index.ts#L841-L858)
- **Uppy UploadPartBytesResult**: [utils.ts:21-24](https://github.com/transloadit/uppy/blob/main/packages/%40uppy/aws-s3/src/utils.ts#L21-L24)
- **Previous Fluppy Plan**: `doc/plans/20260120_flexible-upload-response-body.md`

---

## Implementation Notes

1. **Location Fallback**: For single-part uploads, we still use the presigned URL base (without query params) as fallback if no `Location` header - this matches the pattern of "what URL did we upload to".

2. **S3Utils is Opt-In**: The helper class is for users who want the old convenience behavior. The default is raw responses like Uppy.

3. **No Internal Changes to S3Part**: The `S3Part` class already handles `ETag` capitalization in `fromJson`/`toJson` for S3 API compatibility. Internal fields remain lowercase.

4. **ETag Convention**: Fluppy uses lowercase `eTag` consistently. Uppy's capitalized `ETag` backward compatibility is not needed since Fluppy never used that format.
