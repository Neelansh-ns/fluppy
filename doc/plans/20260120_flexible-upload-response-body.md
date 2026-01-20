# Flexible Upload Response Body Implementation Plan

| Field | Value |
|-------|-------|
| **Created** | 2026-01-20 |
| **Last Updated** | 2026-01-20 |
| **Uppy Reference** | [UppyFile.response](https://github.com/transloadit/uppy/blob/main/packages/%40uppy/utils/src/UppyFile.ts#L33-L38) |
| **Status** | Complete |

## Overview

Add a flexible `body` field to `UploadResponse` and `CompleteMultipartResult` to allow passing custom data from backend callbacks through to the final upload response. This aligns Fluppy with Uppy's approach where `response.body` contains the complete backend response.

**Problem Statement**: Currently, `CompleteMultipartResult` only has `location` and `eTag` fields. Users cannot pass additional custom data (e.g., `mediaId`, `blobId`, custom metadata) from their `completeMultipartUpload` callback to the final `UploadResponse`.

**Uppy Equivalent**: In Uppy, the `response.body` field is generic (`B extends Body = Record<string, unknown>`) and carries the entire backend response through to completion events.

## Current State Analysis

### What Exists

**`CompleteMultipartResult`** ([lib/src/s3/s3_types.dart:215-226](lib/src/s3/s3_types.dart#L215-L226)):
```dart
class CompleteMultipartResult {
  final String? location;
  final String? eTag;
  // No way to pass custom data!
}
```

**`UploadResponse`** ([lib/src/core/types.dart:90-107](lib/src/core/types.dart#L90-L107)):
```dart
class UploadResponse {
  final String? location;
  final String? eTag;      // S3-specific - shouldn't be in core
  final String? key;       // S3-specific - shouldn't be in core
  final Map<String, dynamic>? metadata;  // Exists but never populated!
}
```

**`MultipartUploadController._completeUpload()`** ([lib/src/s3/multipart_upload_controller.dart:548-613](lib/src/s3/multipart_upload_controller.dart#L548-L613)):
```dart
return UploadResponse(
  location: location,
  eTag: result.eTag,
  key: file.s3Multipart.key,
  // metadata is never set!
);
```

### What's Wrong

1. **S3-specific fields in core type**: `eTag` and `key` in `UploadResponse` are S3-specific but live in core types
2. **No data passthrough**: Custom data from `completeMultipartUpload` callback cannot reach `UploadResponse`
3. **Unused `metadata` field**: `UploadResponse.metadata` exists but is never populated
4. **Single-part uploads**: Also construct `UploadResponse` without custom data capability

### Uppy's Approach (Reference)

From [UppyFile.ts](https://github.com/transloadit/uppy/blob/main/packages/%40uppy/utils/src/UppyFile.ts#L33-L38):
```typescript
response?: {
  body?: B           // Generic - contains ENTIRE backend response
  status: number
  bytesUploaded?: number
  uploadURL?: string  // Same as location
}
```

From [AWS S3 onSuccess](https://github.com/transloadit/uppy/blob/main/packages/%40uppy/aws-s3/src/index.ts#L841-L859):
```typescript
const onSuccess = (result: B) => {
  const uploadResp = {
    body: { ...result },  // Full response spread into body
    status: 200,
    uploadURL: result.location,
  }
  this.uppy.emit('upload-success', file, uploadResp)
}
```

## Desired End State

After implementation:

1. **`CompleteMultipartResult`** has a `body` field for custom data
2. **`UploadResponse`** has a `body` field that receives the custom data
3. **S3-specific fields** (`eTag`, `key`) are removed from `UploadResponse` - access via `body` instead
4. **Single-part uploads** also include S3 fields in `body`
5. **Users can pass any data** from their backend through to completion events

**Example Usage After Implementation**:
```dart
// User's completeMultipartUpload callback
completeMultipartUpload: (file, options) async {
  final response = await myBackend.completeUpload(...);
  return CompleteMultipartResult(
    location: response.url,
    body: {
      'mediaId': response.mediaId,
      'blobId': response.blobId,
      'thumbnailUrl': response.thumbnailUrl,
      'customField': response.customField,
    },
  );
},

// In completion event
fluppy.events.listen((event) {
  if (event is UploadComplete) {
    final mediaId = event.response.body?['mediaId'];
    final blobId = event.response.body?['blobId'];
    // Use custom data...
  }
});
```

**Success Criteria:**
- [x] `CompleteMultipartResult` accepts custom `body` data
- [x] `UploadResponse.body` contains the custom data
- [x] S3-specific fields (`eTag`, `key`, `metadata`) removed from `UploadResponse`
- [x] S3 fields accessible via `body?['eTag']` and `body?['key']`
- [x] Single-part uploads include S3 fields in `body`
- [x] All tests updated and pass
- [x] Example demonstrates new usage
- [x] Migration guide documents breaking changes

## Uppy Alignment

### Uppy's Implementation
- `response.body` is generic type `B` (defaults to `Record<string, unknown>`)
- The entire backend response flows through to `body`
- `uploadURL` (equivalent to `location`) is the only "standard" extracted field
- No S3-specific fields in core response type

### Fluppy Adaptation Strategy
- Use `Map<String, dynamic>?` for `body` (Dart equivalent of `Record<string, unknown>`)
- Keep `location` as the standard field
- Remove S3-specific fields (`eTag`, `key`) from core type - access via `body` instead
- Remove unused `metadata` field (replaced by `body`)

**Field Mapping:**
| Uppy Field | Fluppy Field | Notes |
|------------|--------------|-------|
| `response.body` | `UploadResponse.body` | `Map<String, dynamic>?` |
| `response.uploadURL` | `UploadResponse.location` | Standard location field |
| `response.status` | N/A | Not needed for Fluppy |
| S3 `eTag` | `body?['eTag']` | In body, not top-level |
| S3 `key` | `body?['key']` | In body, not top-level |

## What We're NOT Doing

1. **Not making types generic** - Using `Map<String, dynamic>` instead of generic `<T>` for simplicity
2. **Not adding file metadata storage** - That's a separate feature (like Uppy's `setFileMeta`)
3. **Not changing event types** - `UploadComplete` event structure remains the same

## Breaking Changes

This is a **breaking change** release. The following fields are **removed** from `UploadResponse`:
- `eTag` - Access via `body?['eTag']` instead
- `key` - Access via `body?['key']` instead
- `metadata` - Replaced by `body`

## Implementation Approach

The implementation follows a bottom-up approach:
1. First, update the S3-specific types (`CompleteMultipartResult`)
2. Then, update the core types (`UploadResponse`)
3. Finally, update the controllers and uploaders to pass data through

---

## Phase 1: Update Core Types

### Overview
Update `UploadResponse` to have a proper `body` field and deprecate S3-specific fields.

### Files to Modify

#### 1. `lib/src/core/types.dart`

**Changes**:
- Add `body` field to `UploadResponse`
- **Remove** `eTag` field (S3-specific, now in `body`)
- **Remove** `key` field (S3-specific, now in `body`)
- **Remove** `metadata` field (unused, replaced by `body`)

```dart
/// Response from a completed upload.
///
/// The [body] field contains the complete response from the upload backend,
/// allowing custom data to flow through from upload callbacks.
///
/// For S3 uploads, standard fields like `eTag` and `key` are available in [body]:
/// ```dart
/// final eTag = response.body?['eTag'] as String?;
/// final key = response.body?['key'] as String?;
/// ```
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
  /// For S3 uploads, this includes:
  /// - `eTag`: The ETag of the uploaded object
  /// - `key`: The object key in the S3 bucket
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
```

**Why**:
- Aligns with Uppy's `response.body` pattern
- Removes S3-specific fields from core types
- Provides flexibility for any upload backend

### Success Criteria
- [x] `UploadResponse` has `body` field
- [x] `eTag`, `key`, and `metadata` fields are removed
- [x] Code compiles without errors

---

## Phase 2: Update S3 Types

### Overview
Add `body` field to `CompleteMultipartResult` to allow passing custom data from the callback.

### Files to Modify

#### 1. `lib/src/s3/s3_types.dart`

**Changes**: Add `body` field to `CompleteMultipartResult`

```dart
/// Result from completing a multipart upload.
///
/// The [body] field allows passing custom data from your backend response
/// through to the final [UploadResponse].
///
/// Example:
/// ```dart
/// completeMultipartUpload: (file, options) async {
///   final response = await myBackend.completeUpload(...);
///   return CompleteMultipartResult(
///     location: response.url,
///     body: {
///       'mediaId': response.mediaId,
///       'blobId': response.blobId,
///       'thumbnailUrl': response.thumbnailUrl,
///     },
///   );
/// },
/// ```
class CompleteMultipartResult {
  /// The public URL to the uploaded file (if available).
  final String? location;

  /// The ETag of the completed object.
  ///
  /// Note: This is also included in [body] when provided, for convenience.
  final String? eTag;

  /// Custom response data from the upload backend.
  ///
  /// This data flows through to [UploadResponse.body], allowing you to
  /// pass any custom fields from your `completeMultipartUpload` callback
  /// to the upload completion event.
  ///
  /// Common use cases:
  /// - Backend-generated IDs (mediaId, blobId, etc.)
  /// - Processing status or metadata
  /// - Thumbnail URLs or derived assets
  /// - Any application-specific data
  final Map<String, dynamic>? body;

  const CompleteMultipartResult({
    this.location,
    this.eTag,
    this.body,
  });

  @override
  String toString() => 'CompleteMultipartResult(location: $location, body: $body)';
}
```

**Why**: Allows users to return custom data from their `completeMultipartUpload` callback.

### Success Criteria
- [x] `CompleteMultipartResult` has `body` field
- [x] Field is optional (backwards compatible)
- [x] Dartdoc explains usage clearly

---

## Phase 3: Update Multipart Upload Controller

### Overview
Wire up the `body` field from `CompleteMultipartResult` to `UploadResponse`.

### Files to Modify

#### 1. `lib/src/s3/multipart_upload_controller.dart`

**Changes**: Update `_completeUpload()` to pass `body` through

**Current code** (lines 548-613):
```dart
Future<UploadResponse> _completeUpload() async {
  // ... existing code ...

  final result = await options.completeMultipartUpload(...);

  // ... location decoding logic ...

  return UploadResponse(
    location: location,
    eTag: result.eTag,
    key: file.s3Multipart.key,
  );
}
```

**New code**:
```dart
Future<UploadResponse> _completeUpload() async {
  // ... existing code unchanged until return statement ...

  final result = await options.completeMultipartUpload(...);

  // ... location decoding logic unchanged ...

  // Build the response body, merging any custom data with standard fields
  final Map<String, dynamic> responseBody = {
    // Include standard S3 fields in body
    if (result.eTag != null) 'eTag': result.eTag,
    if (file.s3Multipart.key != null) 'key': file.s3Multipart.key,
    // Merge any custom data from the callback (takes precedence)
    if (result.body != null) ...result.body!,
  };

  return UploadResponse(
    location: location,
    body: responseBody.isNotEmpty ? responseBody : null,
  );
}
```

**Why**:
- Passes custom `body` data through to `UploadResponse`
- Includes standard S3 fields (`eTag`, `key`) in `body`
- Custom data from callback takes precedence if keys overlap

### Success Criteria
- [x] `CompleteMultipartResult.body` flows to `UploadResponse.body`
- [x] Standard S3 fields (`eTag`, `key`) included in `body`
- [x] Custom body data takes precedence over standard fields

---

## Phase 4: Update Single-Part Upload

### Overview
Add `body` support to single-part uploads for consistency.

### Files to Modify

#### 1. `lib/src/s3/s3_uploader.dart`

**Changes**: Update `_uploadSinglePart()` to include `body` in response

**Current code** (around line 401-404):
```dart
return UploadResponse(
  location: location,
  eTag: eTag,
);
```

**New code**:
```dart
// Build response body with S3 fields
final Map<String, dynamic> responseBody = {
  if (eTag != null) 'eTag': eTag,
  if (objectKey != null) 'key': objectKey,
};

return UploadResponse(
  location: location,
  body: responseBody.isNotEmpty ? responseBody : null,
);
```

**Why**: Ensures consistent behavior between single-part and multipart uploads.

### Success Criteria
- [x] Single-part uploads include `body` with S3 fields
- [x] Consistent with multipart behavior

---

## Phase 5: Update Tests and Examples

### Overview
Update tests to verify new functionality and add example demonstrating usage.

### Tests to Add/Modify

#### 1. `test/upload_response_test.dart` (new file)

```dart
import 'package:fluppy/fluppy.dart';
import 'package:test/test.dart';

void main() {
  group('UploadResponse', () {
    test('body field contains custom data', () {
      final response = UploadResponse(
        location: 'https://example.com/file.jpg',
        body: {
          'mediaId': '12345',
          'blobId': 'blob-abc',
          'customField': 'value',
        },
      );

      expect(response.body?['mediaId'], '12345');
      expect(response.body?['blobId'], 'blob-abc');
      expect(response.body?['customField'], 'value');
    });

    test('body includes S3 fields', () {
      final response = UploadResponse(
        location: 'https://example.com/file.jpg',
        body: {
          'eTag': '"abc123"',
          'key': 'uploads/file.jpg',
        },
      );

      expect(response.body?['eTag'], '"abc123"');
      expect(response.body?['key'], 'uploads/file.jpg');
    });

    test('body can be null', () {
      final response = UploadResponse(location: 'https://example.com/file.jpg');
      expect(response.body, isNull);
    });
  });

  group('CompleteMultipartResult', () {
    test('body field passes custom data', () {
      final result = CompleteMultipartResult(
        location: 'https://example.com/file.jpg',
        eTag: '"abc123"',
        body: {
          'mediaId': '12345',
          'processingStatus': 'complete',
        },
      );

      expect(result.body?['mediaId'], '12345');
      expect(result.body?['processingStatus'], 'complete');
    });
  });
}
```

#### 2. Update `example/example.dart`

Add example showing custom body usage:

```dart
// In the S3UploaderOptions configuration:
completeMultipartUpload: (file, options) async {
  // Call your backend to complete the upload
  final response = await yourBackend.completeUpload(
    uploadId: options.uploadId,
    key: options.key,
    parts: options.parts,
  );

  // Return result with custom body data
  return CompleteMultipartResult(
    location: response.url,
    eTag: response.eTag,
    body: {
      // Pass any custom data from your backend
      'mediaId': response.mediaId,
      'blobId': response.blobId,
      'thumbnailUrl': response.thumbnailUrl,
      'processingJobId': response.processingJobId,
    },
  );
},

// Later, in your completion handler:
fluppy.events.listen((event) {
  if (event is UploadComplete) {
    // Access custom data via body
    final mediaId = event.response.body?['mediaId'] as String?;
    final blobId = event.response.body?['blobId'] as String?;

    print('Upload complete! Media ID: $mediaId, Blob ID: $blobId');
  }
});
```

### Success Criteria
- [x] New test file created and passes
- [x] Example demonstrates custom body usage
- [x] All existing tests still pass

---

## Testing Strategy

### Unit Tests
- `UploadResponse` accepts and returns `body` data
- `CompleteMultipartResult` accepts and returns `body` data
- S3 fields (`eTag`, `key`) accessible via `body`

### Integration Tests
- Multipart upload with custom `body` data flows to completion event
- Single-part upload includes S3 fields in `body`
- S3 fields accessible via `body?['eTag']` and `body?['key']`

### Manual Testing
1. Create a test upload with custom `completeMultipartUpload` returning body data
2. Verify body data appears in `UploadComplete` event
3. Verify S3 fields accessible via `body`

## Documentation Updates

### API Documentation
- [ ] Update dartdoc for `UploadResponse`
- [ ] Update dartdoc for `CompleteMultipartResult`
- [ ] Add deprecation notices for `eTag` and `key`

### README Updates
- [ ] Add section on accessing custom response data
- [ ] Show migration path from deprecated fields

### Example in README
```dart
// Returning custom data from completeMultipartUpload
completeMultipartUpload: (file, options) async {
  final response = await backend.complete(...);
  return CompleteMultipartResult(
    location: response.url,
    body: {'mediaId': response.mediaId, 'status': response.status},
  );
},

// Accessing in completion event
fluppy.events.listen((event) {
  if (event is UploadComplete) {
    print('Media ID: ${event.response.body?["mediaId"]}');
  }
});
```

## Migration Guide

### Breaking Change: `eTag` and `key` Fields Removed

**Before (old API)**:
```dart
fluppy.events.listen((event) {
  if (event is UploadComplete) {
    final eTag = event.response.eTag;  // REMOVED
    final key = event.response.key;    // REMOVED
  }
});
```

**After (new API)**:
```dart
fluppy.events.listen((event) {
  if (event is UploadComplete) {
    final eTag = event.response.body?['eTag'] as String?;
    final key = event.response.body?['key'] as String?;
  }
});
```

### New Feature: Custom Data Passthrough

**Before (not possible)**:
```dart
// No way to pass custom data through!
```

**After**:
```dart
// In options
completeMultipartUpload: (file, options) async {
  final response = await backend.complete(...);
  return CompleteMultipartResult(
    location: response.url,
    body: {
      'mediaId': response.mediaId,
      'blobId': response.blobId,
      'anyCustomField': response.customField,
    },
  );
},

// In event handler
fluppy.events.listen((event) {
  if (event is UploadComplete) {
    final mediaId = event.response.body?['mediaId'];
    final blobId = event.response.body?['blobId'];
  }
});
```

---

## References

- **Uppy UppyFile.ts**: [GitHub](https://github.com/transloadit/uppy/blob/main/packages/%40uppy/utils/src/UppyFile.ts)
- **Uppy AWS S3 Plugin**: [GitHub](https://github.com/transloadit/uppy/blob/main/packages/%40uppy/aws-s3/src/index.ts)
- **Uppy Documentation**: [uppy.io/docs/aws-s3](https://uppy.io/docs/aws-s3/)

## Open Questions

None - all design decisions resolved.

---

## Implementation Notes

1. **Breaking Change**: This version removes `eTag`, `key`, and `metadata` fields from `UploadResponse`. Users must migrate to using `body`.

2. **Body Merging**: Custom body data from callbacks takes precedence. If the user's body contains `eTag`, it will override the standard S3 eTag in the merged body.

3. **Null Safety**: `body` is nullable. Users should use null-aware access (`body?['field']`).

4. **Type Safety**: Since `body` is `Map<String, dynamic>`, users need to cast values:
   ```dart
   final mediaId = response.body?['mediaId'] as String?;
   final count = response.body?['count'] as int?;
   ```

5. **S3 Fields in Body**: For S3 uploads, standard fields are automatically included in `body`:
   - `body?['eTag']` - The ETag of the uploaded object
   - `body?['key']` - The object key in the S3 bucket

---

## Appendix: Location Field Comparison (Uppy vs Fluppy)

This section documents how Uppy.js and Fluppy handle the `location` field construction, based on code analysis.

### Uppy.js Approach

**Single-part uploads** ([index.ts:763](https://github.com/transloadit/uppy/blob/main/packages/%40uppy/aws-s3/src/index.ts#L763)):
```typescript
const { etag, location } = headersMap

// If POST method and no location header, logs error about CORS
if (method.toUpperCase() === 'POST' && location == null) {
  console.error('@uppy/aws-s3: Could not read the Location header...')
}
```
- Reads `location` directly from HTTP response headers
- No automatic URL construction
- Requires proper CORS configuration to expose headers

**Multipart uploads** ([index.ts:841-858](https://github.com/transloadit/uppy/blob/main/packages/%40uppy/aws-s3/src/index.ts#L841-L858)):
```typescript
const onSuccess = (result: B) => {
  const uploadResp = {
    body: { ...result },
    status: 200,
    uploadURL: result.location as string,  // Uses callback return
  }
}
```
- Uses `result.location` from the `completeMultipartUpload` callback
- Callback return type: `MaybePromise<{ location?: string }>` ([line 229](https://github.com/transloadit/uppy/blob/main/packages/%40uppy/aws-s3/src/index.ts#L229))
- No fallback construction

### Fluppy Approach

**Single-part uploads** ([s3_uploader.dart:368-399](lib/src/s3/s3_uploader.dart#L368-L399)):
```dart
String location;
if (tempCredentials != null && objectKey != null) {
  // Construct URL from bucket/region/key
  location = 'https://${tempCredentials.bucket}.s3.${tempCredentials.region}.amazonaws.com/$pathSegments';
} else {
  // Use response header or presigned URL base
  location = response.headers['location'] ?? params.url.split('?').first;
}
```
- **With temp credentials**: Constructs URL from bucket/region/key
- **Without temp credentials**: Uses response headers or presigned URL base
- **Decodes URL paths** for cleaner display

**Multipart uploads** ([multipart_upload_controller.dart:569-606](lib/src/s3/multipart_upload_controller.dart#L569-L606)):
```dart
String? location = result.location;
if (location != null) {
  // Decode for cleaner display
  location = '${uri.scheme}://${uri.authority}$decodedPath';
} else if (getTemporaryCredentials != null && file.s3Multipart.key != null) {
  // Construct from temp credentials if not provided
  final credentials = await getTemporaryCredentials!();
  location = 'https://${credentials.bucket}.s3.${credentials.region}.amazonaws.com/$pathSegments';
}
```
- **Primary**: Uses `result.location` from callback (same as Uppy)
- **Fallback**: Constructs URL from temp credentials if location not provided
- **Decodes URL paths** for cleaner display

### Comparison Summary

| Aspect | Uppy.js | Fluppy |
|--------|---------|--------|
| **Single-part source** | HTTP response headers only | Headers OR constructed from temp creds |
| **Multipart source** | Callback return only | Callback return OR constructed from temp creds |
| **Fallback construction** | None | Yes - from temporary credentials |
| **URL path decoding** | No | Yes - for cleaner display |
| **CORS requirement** | Must expose `Location` header | Works without (when using temp creds) |

### Key Differences

1. **Convenience vs Strictness**: Fluppy provides more convenience by constructing URLs when not provided by the backend, while Uppy requires the backend to always provide the location.

2. **Temp Credentials Support**: Fluppy's approach is particularly helpful when using client-side signing with temporary credentials, as the URL can be constructed without a backend round-trip.

3. **URL Decoding**: Fluppy decodes URL paths (e.g., `%2F` → `/`) for cleaner display, while Uppy preserves the raw URL as received.

4. **Backward Compatibility**: Fluppy's fallback construction ensures `location` is available even when backends don't return it, making migration easier.

### Recommendation

**UPDATE**: After further discussion, we decided to align with Uppy's approach for consistency and flexibility. See the follow-up plan: `doc/plans/20260120_uppy-aligned-response-handling.md`

The changes will:
- Remove automatic URL construction and decoding (return raw responses like Uppy)
- Expose `S3Utils` helper class for users who want the convenience features
- Add ETag backward compatibility (both `etag` and `ETag` in response)

This gives users more control while still providing opt-in helpers for URL manipulation.
