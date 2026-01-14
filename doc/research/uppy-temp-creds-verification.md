# Uppy Temporary Credentials Implementation Verification

**Date**: 2026-01-13  
**Source**: [Official Uppy Documentation](https://uppy.io/docs/aws-s3/#gettemporarysecuritycredentialsoptions)

---

## Key Findings

### 1. Callback Behavior When Temp Creds Provided

**✅ CONFIRMED**: When `getTemporarySecurityCredentials` is provided:

- **`getUploadParameters`** - **NOT called** (Uppy signs client-side)
- **`signPart`** - **NOT called** (Uppy signs client-side)
- **`createMultipartUpload`** - **STILL called** (S3 API operation)
- **`completeMultipartUpload`** - **STILL called** (S3 API operation)
- **`listParts`** - **STILL called** (S3 API operation for resume)
- **`abortMultipartUpload`** - **STILL called** (S3 API operation for cleanup)

**Rationale**: Temp creds allow client-side signing, but S3 API calls still require backend.

---

### 2. Return Format

Uppy expects:

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

**✅ VERIFIED**: Our `TemporaryCredentials.fromJson()` already handles this format correctly:

- Supports nested `credentials` object (Uppy format)
- Also supports flat structure (backward compatibility)
- Parses `Expiration` as ISO 8601 DateTime

---

### 3. Object Key Strategy

**Single-Part Uploads**:

- Uses `file.name` as the object key
- No backend callback needed for key generation

**Multipart Uploads**:

- Uses `key` returned from `createMultipartUpload`
- Backend determines the key during multipart creation

**✅ ALIGNMENT**: Our plan matches this - default to `file.name`, allow optional `getObjectKey` callback.

---

### 4. Implementation Flow

**Single-Part** (with temp creds):

```
1. Get temp credentials (cached if valid)
2. Use file.name as object key
3. Sign URL client-side using AwsSignatureV4
4. Upload directly to S3
```

**Multipart** (with temp creds):

```
1. Call createMultipartUpload → Get { uploadId, key }
2. Get temp credentials (cached if valid)
3. For each part:
   a. Sign part URL client-side using AwsSignatureV4 (key from step 1)
   b. Upload part directly to S3
4. Call completeMultipartUpload → Finalize
```

---

### 5. Benefits & Trade-offs

**Benefits** (per Uppy docs):

- ~20% faster uploads
- Reduced server load (no signing requests)
- Less request overhead

**Trade-offs**:

- Credentials exposed to client (security consideration)
- Must use temporary credentials only (not long-lived)
- Requires proper IAM policy scoping

---

## Fluppy Implementation Status

### ✅ Already Implemented

1. **`TemporaryCredentials` class** - Matches Uppy format
2. **`AwsSignatureV4` signing** - Client-side signing implementation
3. **Credential caching** - 5-minute expiration buffer (matches Uppy pattern)
4. **`getTemporarySecurityCredentials` callback** - API matches Uppy

### ❌ Missing Integration

1. **Single-part upload** - Still calls `getUploadParameters` even when temp creds available
2. **Multipart upload** - Still calls `signPart` even when temp creds available
3. **Object key handling** - Need to use `file.name` for single-part, `key` from `createMultipartUpload` for multipart
4. **Tests** - No tests for actual uploads using temp creds

---

## Implementation Checklist

Based on Uppy documentation, we need to:

- [ ] Modify `_uploadSinglePart()` to check for temp creds and sign client-side
- [ ] Modify `MultipartUploadController._uploadPart()` to check for temp creds and sign client-side
- [ ] Use `file.name` as object key for single-part uploads
- [ ] Use `key` from `createMultipartUpload` for multipart part signing
- [ ] Ensure `getUploadParameters` and `signPart` are NOT called when temp creds available
- [ ] Keep `createMultipartUpload`, `completeMultipartUpload`, `listParts`, `abortMultipartUpload` callbacks required
- [ ] Add comprehensive tests for temp creds upload flow
- [ ] Update documentation with temp creds examples

---

## Verification

**Source**: [Uppy AWS S3 Documentation - getTemporarySecurityCredentials](https://uppy.io/docs/aws-s3/#gettemporarysecuritycredentialsoptions)

**Key Quote**: "used for all uploads instead of signing every part"

This confirms that when temp creds are provided, Uppy completely bypasses the signing callbacks (`getUploadParameters` and `signPart`) and performs signing client-side.

---

## Next Steps

1. ✅ Verify plan matches Uppy behavior (this document)
2. ⏭️ Implement Phase 1: Single-part upload integration
3. ⏭️ Implement Phase 2: Multipart upload integration
4. ⏭️ Add tests and documentation
