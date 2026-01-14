# Plan: Temporary Credentials Integration for S3 Uploads

**Status**: Planning  
**Created**: 2026-01-13  
**Related**: [Uppy Temporary Credentials Mode](https://uppy.io/docs/aws-s3/#temporary-credentials-mode)

---

## Uppy Documentation Analysis

Based on the [official Uppy documentation](https://uppy.io/docs/aws-s3/#gettemporarysecuritycredentialsoptions), here are the key findings:

### When Temp Creds Are Provided

**Callbacks NOT called** (Uppy signs client-side):

- ❌ `getUploadParameters` - Bypassed, Uppy signs single-part URLs client-side
- ❌ `signPart` - Bypassed, Uppy signs part URLs client-side

**Callbacks STILL called** (S3 API operations):

- ✅ `createMultipartUpload` - Returns `{ uploadId, key }`
- ✅ `completeMultipartUpload` - Finalizes multipart upload
- ✅ `listParts` - Lists uploaded parts (for resume)
- ✅ `abortMultipartUpload` - Cleans up failed uploads

### Return Format

```javascript
{
  credentials: {
    AccessKeyId: string,
    SecretAccessKey: string,
    SessionToken: string,
    Expiration: string  // ISO 8601 format
  },
  bucket: string,
  region: string
}
```

### Object Key Strategy

- **Single-part**: Uses `file.name` as the object key
- **Multipart**: Uses `key` returned from `createMultipartUpload`

### Benefits

- ~20% faster uploads (reduced request overhead)
- Reduced server load (no signing requests)
- Security trade-off: Credentials exposed to client (must use temp creds only!)

---

## Problem Statement

The Fluppy codebase has **two ways** to implement S3 uploads:

1. **Custom Backend Mode** (✅ Fully implemented and tested)

   - Backend generates presigned URLs via callbacks (`getUploadParameters`, `signPart`, etc.)
   - Each upload operation requires a backend round-trip for signing
   - Works for both single-part and multipart uploads

2. **Temporary Credentials Mode** (⚠️ Partially implemented, NOT integrated)
   - Infrastructure exists: `getTemporarySecurityCredentials`, `AwsSignatureV4`, credential caching
   - **BUT**: Not actually used in the upload flow
   - Upload flow still requires all backend callbacks even when temp credentials are provided
   - Missing integration: Temp creds should sign URLs client-side instead of calling backend

**Current State**:

- ✅ `TemporaryCredentials` class exists
- ✅ `AwsSignatureV4` signing implementation exists
- ✅ Credential caching/refresh logic exists
- ✅ Tests for credential caching exist
- ❌ **NOT integrated into upload flow** - `_uploadSinglePart()` and `MultipartUploadController` don't use temp creds
- ❌ **No tests** for actual uploads using temp credentials
- ❌ **No examples** showing temp credentials usage

**Uppy Reference**: According to [official Uppy documentation](https://uppy.io/docs/aws-s3/#gettemporarysecuritycredentialsoptions), when `getTemporarySecurityCredentials` is provided:

- Uppy signs URLs **client-side** using AWS SDK, eliminating the need for `getUploadParameters` and `signPart` callbacks
- Results in ~20% faster uploads due to reduced request overhead
- Still requires backend callbacks for S3 API operations: `createMultipartUpload`, `completeMultipartUpload`, `listParts`, `abortMultipartUpload`
- Returns object with `credentials` (AccessKeyId, SecretAccessKey, SessionToken, Expiration), `bucket`, and `region`

---

## Goals

1. **Integrate temporary credentials into upload flow**

   - Single-part uploads: Sign URLs client-side when temp creds available
   - Multipart uploads: Sign part URLs client-side when temp creds available
   - Fallback: Still support backend callbacks when temp creds not provided

2. **Maintain backward compatibility**

   - Existing backend-only mode continues to work
   - Temp creds mode is optional enhancement

3. **Complete test coverage**

   - Unit tests for temp creds upload flow
   - Integration tests verifying end-to-end uploads
   - Edge cases: credential expiration during upload, refresh logic

4. **Documentation and examples**
   - Update README with temp creds usage
   - Add example showing temp creds mode
   - Document when to use temp creds vs backend mode

---

## Architecture Analysis

### Current Upload Flow (Backend Mode)

**Single-Part**:

```
1. Call options.getUploadParameters(file) → Get presigned URL from backend
2. Upload file to presigned URL
```

**Multipart**:

```
1. Call options.createMultipartUpload(file) → Get uploadId/key from backend
2. For each part:
   a. Call options.signPart(file, partData) → Get presigned URL from backend
   b. Upload part to presigned URL
3. Call options.completeMultipartUpload(file, parts) → Finalize on backend
```

### Desired Upload Flow (Temp Creds Mode)

**Single-Part** (per [Uppy docs](https://uppy.io/docs/aws-s3/#gettemporarysecuritycredentialsoptions)):

```
1. Get temp credentials (cached if valid) → Contains bucket, region, credentials
2. Determine object key → Use file.name (or callback if provided)
3. Use AwsSignatureV4 to sign URL client-side → No backend call needed!
4. Upload file to presigned URL
```

**Multipart** (per [Uppy docs](https://uppy.io/docs/aws-s3/#gettemporarysecuritycredentialsoptions)):

```
1. Call options.createMultipartUpload(file) → Still need backend for S3 API
   → Returns: { uploadId, key }
2. Get temp credentials (cached if valid) → Contains bucket, region, credentials
3. For each part:
   a. Use AwsSignatureV4 to sign part URL client-side → No signPart callback!
   b. Upload part to presigned URL
4. Call options.completeMultipartUpload(file, parts) → Still need backend for S3 API
5. Call options.listParts(file, { uploadId, key }) → Still need backend for resume
6. Call options.abortMultipartUpload(file, { uploadId, key }) → Still need backend for cleanup
```

**Key Insights from Uppy Documentation**:

- ✅ **When temp creds provided**: `getUploadParameters` and `signPart` callbacks are **NOT called** - Uppy signs client-side
- ✅ **Still need backend for**: `createMultipartUpload`, `completeMultipartUpload`, `listParts`, `abortMultipartUpload` (these are S3 API calls, not just signing)
- ✅ **Object key**: For single-part, use `file.name`. For multipart, use `key` returned from `createMultipartUpload`
- ✅ **Return format**: `{ credentials: { AccessKeyId, SecretAccessKey, SessionToken, Expiration }, bucket, region }`

---

## Implementation Plan

### Phase 1: Single-Part Upload Integration

**Goal**: Use temp credentials to sign single-part upload URLs client-side.

**Changes**:

1. Modify `S3Uploader._uploadSinglePart()`:

   - Check if `hasTemporaryCredentials`
   - If yes: Get temp creds → Sign URL client-side → Upload
   - If no: Fall back to `getUploadParameters` callback (existing flow)

2. Determine object key:

   - **Per Uppy docs**: Use `file.name` as the object key for single-part uploads
   - **Optional enhancement**: Add `getObjectKey` callback for custom key generation (matches Uppy's flexibility)
   - **Decision**: Default to `file.name`, allow optional `getObjectKey` callback for custom logic

3. Handle credential expiration:
   - Check credentials before signing
   - Refresh if expired (with 5 min buffer)
   - Handle refresh failures gracefully

**Files to Modify**:

- `lib/src/s3/s3_uploader.dart` - `_uploadSinglePart()` method
- `lib/src/s3/s3_options.dart` - Add optional `getObjectKey` callback

**Tests to Add**:

- Single-part upload with temp creds
- Fallback to backend when temp creds not provided
- Credential refresh during upload
- Invalid/expired credentials handling

---

### Phase 2: Multipart Upload Integration

**Goal**: Use temp credentials to sign multipart part URLs client-side.

**Changes**:

1. Modify `MultipartUploadController._uploadPart()`:

   - Check if uploader has temp credentials
   - If yes: Get temp creds → Sign part URL client-side using `key` from `createMultipartUpload` → Upload
   - If no: Fall back to `signPart` callback (existing flow)
   - **Per Uppy**: When temp creds provided, `signPart` callback is NOT called

2. Pass credentials to controller:

   - Add `S3Uploader` reference to controller (to access `getTemporaryCredentials()`)
   - Controller already has access to `key` from `createMultipartUpload` result

3. Handle credential expiration:
   - Check credentials before each part sign
   - Refresh if needed
   - Handle refresh failures

**Files to Modify**:

- `lib/src/s3/multipart_upload_controller.dart` - `_uploadPart()` method
- `lib/src/s3/s3_uploader.dart` - Pass credentials access to controller

**Tests to Add**:

- Multipart upload with temp creds
- Fallback to backend when temp creds not provided
- Credential refresh during multipart upload
- Resume with temp creds (verify parts signed correctly)

---

### Phase 3: Configuration and API Refinement

**Goal**: Make temp creds mode easy to use and well-documented.

**Changes**:

1. Add convenience methods:

   - `S3UploaderOptions.withTemporaryCredentials()` factory
   - Helper for common temp creds patterns

2. Improve error messages:

   - Clear errors when temp creds missing required fields
   - Guidance on when to use temp creds vs backend

3. Key generation strategy:
   - Default: Use `file.name`
   - Optional: `getObjectKey` callback for custom logic
   - Document best practices

**Files to Modify**:

- `lib/src/s3/s3_options.dart` - Add factory/helpers
- `lib/src/s3/s3_uploader.dart` - Improve error handling

**Tests to Add**:

- Configuration validation
- Error message clarity

---

### Phase 4: Testing and Documentation

**Goal**: Comprehensive test coverage and clear documentation.

**Changes**:

1. **Unit Tests** (`test/s3_uploader_test.dart`):

   - Single-part upload with temp creds
   - Multipart upload with temp creds
   - Credential refresh scenarios
   - Fallback to backend mode
   - Edge cases (expired creds, network failures)

2. **Integration Tests** (`test/integration/s3_integration_test.dart`):

   - End-to-end upload with temp creds
   - Compare performance vs backend mode
   - Verify S3 compatibility

3. **Documentation**:
   - Update README with temp creds example
   - Add to `example/example.dart`
   - Document security considerations
   - Migration guide from backend mode

**Files to Modify**:

- `test/s3_uploader_test.dart` - Add temp creds tests
- `test/integration/s3_integration_test.dart` - Add temp creds integration tests
- `README.md` - Document temp creds mode
- `example/example.dart` - Add temp creds example
- `CHANGELOG.md` - Document new feature

---

## Success Criteria

### Functional Requirements

- [ ] Single-part uploads work with temp credentials
- [ ] Multipart uploads work with temp credentials
- [ ] Fallback to backend mode when temp creds not provided
- [ ] Credential caching/refresh works correctly
- [ ] Resume works with temp creds
- [ ] Pause/resume works with temp creds

### Test Coverage

- [ ] Unit tests for temp creds upload flow (>80% coverage)
- [ ] Integration tests for end-to-end uploads
- [ ] Edge case tests (expired creds, refresh failures)
- [ ] Backward compatibility tests (backend mode still works)

### Documentation

- [ ] README updated with temp creds example
- [ ] Example code demonstrates temp creds usage
- [ ] Security considerations documented
- [ ] Migration guide available

### Uppy Alignment

- [ ] API matches Uppy's temp creds pattern
- [ ] Behavior matches Uppy (client-side signing, backend for S3 API calls)
- [ ] Performance improvement similar to Uppy (~20% faster)

---

## Implementation Details

### Key Design Decisions

1. **Object Key Generation**:

   - Default: `file.name`
   - Optional: `getObjectKey(FluppyFile file) → String` callback
   - Rationale: Flexible, allows custom naming while providing sensible default

2. **Credential Access in Controller**:

   - Pass `S3Uploader` reference to controller
   - Controller calls `uploader.getTemporaryCredentials()`
   - Rationale: Keeps credential management centralized in uploader

3. **Backend Callbacks Still Required**:

   - `createMultipartUpload` - Required (S3 API call)
   - `completeMultipartUpload` - Required (S3 API call)
   - `listParts` - Required (S3 API call for resume)
   - `abortMultipartUpload` - Required (S3 API call)
   - Rationale: These require S3 API calls, not just URL signing

4. **Error Handling**:
   - If temp creds fail to refresh → Fall back to backend mode (if callbacks available)
   - If temp creds invalid → Clear error message
   - Rationale: Graceful degradation, better UX

---

## Testing Strategy

### Unit Tests

**Single-Part with Temp Creds**:

```dart
test('single-part upload uses temp credentials to sign URL', () async {
  // Setup temp creds
  // Verify AwsSignatureV4.createPresignedUrl called
  // Verify upload succeeds
});
```

**Multipart with Temp Creds**:

```dart
test('multipart upload uses temp credentials to sign part URLs', () async {
  // Setup temp creds
  // Verify AwsSignatureV4.createPresignedPartUrl called for each part
  // Verify upload succeeds
});
```

**Credential Refresh**:

```dart
test('refreshes expired credentials during upload', () async {
  // Setup creds that expire mid-upload
  // Verify refresh called
  // Verify upload continues successfully
});
```

**Fallback to Backend**:

```dart
test('falls back to backend when temp creds not provided', () async {
  // No temp creds configured
  // Verify getUploadParameters/signPart callbacks called
  // Verify upload succeeds
});
```

### Integration Tests

**End-to-End Upload**:

```dart
test('uploads file to S3 using temp credentials', () async {
  // Real S3 bucket (test environment)
  // Real temp credentials (from STS)
  // Verify file uploaded successfully
  // Verify file accessible at expected location
});
```

**Performance Comparison**:

```dart
test('temp creds mode faster than backend mode', () async {
  // Measure upload time with temp creds
  // Measure upload time with backend
  // Verify temp creds is faster (~20% improvement)
});
```

---

## Security Considerations

1. **Credential Exposure**:

   - Temp creds stored in memory only
   - Never logged or exposed in error messages
   - Credentials cleared on dispose

2. **Credential Scope**:

   - Document IAM permissions required
   - Recommend least-privilege policies
   - Warn against using long-lived credentials

3. **URL Expiration**:
   - Default expiration: 1 hour
   - Configurable per upload
   - Document best practices

---

## Migration Guide

### From Backend Mode to Temp Creds Mode

**Before** (Backend Mode):

```dart
final uploader = S3Uploader(
  options: S3UploaderOptions(
    getUploadParameters: (file, opts) async {
      final response = await backend.getPresignedUrl(file.name);
      return UploadParameters(url: response.url);
    },
    // ... other callbacks
  ),
);
```

**After** (Temp Creds Mode):

```dart
final uploader = S3Uploader(
  options: S3UploaderOptions(
    getTemporarySecurityCredentials: (opts) async {
      final response = await backend.getTempCredentials();
      // Response format: { credentials: { AccessKeyId, SecretAccessKey, SessionToken, Expiration }, bucket, region }
      return TemporaryCredentials.fromJson(response);
    },
    // Still need backend for S3 API operations (not signing!)
    createMultipartUpload: (file) async {
      return await backend.createMultipart(file.name);
    },
    completeMultipartUpload: (file, opts) async {
      return await backend.completeMultipart(opts.uploadId, opts.key, opts.parts);
    },
    listParts: (file, opts) async {
      return await backend.listParts(opts.uploadId, opts.key);
    },
    abortMultipartUpload: (file, opts) async {
      return await backend.abortMultipart(opts.uploadId, opts.key);
    },
    // NOTE: getUploadParameters and signPart are NOT needed when temp creds provided!
  ),
);
```

**Benefits**:

- Fewer backend round-trips (no signing calls)
- ~20% faster uploads
- Reduced server load

**Trade-offs**:

- Credentials exposed to client (use temp creds only!)
- Still need backend for S3 API calls (multipart operations)

---

## Open Questions

1. **Object Key Strategy**: Should we add `getObjectKey` callback or use `file.name`?

   - **Decision**: Default to `file.name` (matches Uppy). Add optional `getObjectKey` callback for flexibility.
   - **Rationale**: Uppy uses `file.name` by default. For multipart, uses `key` from `createMultipartUpload`.

2. **Credential Refresh During Upload**: What happens if creds expire mid-upload?

   - **Decision**: Refresh automatically with 5 min buffer, fail gracefully if refresh fails

3. **Backend Fallback**: Should we fall back to backend if temp creds fail?

   - **Decision**: Yes, if backend callbacks available. Otherwise, fail with clear error.

4. **Multipart Operations**: Can we eliminate backend for multipart operations?
   - **Decision**: No - `createMultipartUpload`, `completeMultipartUpload`, `listParts`, `abortMultipartUpload` require S3 API calls, not just signing.

---

## References

- [Uppy AWS S3 Plugin - Temporary Credentials](https://uppy.io/docs/aws-s3/#gettemporarysecuritycredentialsoptions) - Official documentation
- [Uppy AWS S3 Plugin - Full API Reference](https://uppy.io/docs/aws-s3/) - Complete API documentation
- [AWS Signature Version 4 Signing Process](https://docs.aws.amazon.com/general/latest/gr/signature-version-4.html)
- [AWS STS AssumeRole](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html)
- Existing code: `lib/src/s3/aws_signature_v4.dart`
- Existing code: `lib/src/s3/s3_uploader.dart`

---

## Next Steps

1. **Review and approve this plan**
2. **Phase 1**: Implement single-part upload integration
3. **Phase 2**: Implement multipart upload integration
4. **Phase 3**: Refine configuration and API
5. **Phase 4**: Complete testing and documentation

---

## Notes

- This is a **feature completion** task, not a bug fix
- Backward compatibility is critical - existing backend mode must continue working
- Temp creds mode is an **optional enhancement** - users can continue using backend mode
- Focus on **Uppy alignment** - match Uppy's behavior and API patterns
