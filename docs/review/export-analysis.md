# Export Analysis: Public API vs Internal Implementation

> **Reference:** Based on [Uppy Core API design](https://uppy.io/docs/uppy/) principles

## Key Principles from Uppy

From Uppy's documentation, we learn:

1. **"Mutating these properties should be done through methods"** - File properties should not be directly mutable
2. **No uploader-specific fields** - File objects should be generic, not tied to specific uploaders (S3, Tus, etc.)
3. **Clear separation** - File object represents the file itself, not uploader implementation details
4. **Structured progress** - Progress is a structured object (Fluppy already does this well ✅)

## Current Exports (from `lib/fluppy.dart`)

```dart
// Core exports
export 'src/core/fluppy.dart';           // ✅ Public API
export 'src/core/fluppy_file.dart';     // ⚠️ Has internal fields & mutable status
export 'src/core/events.dart';           // ✅ Public API
export 'src/core/uploader.dart';         // ✅ Public API (but see RetryMixin)

// S3 exports
export 'src/s3/s3_uploader.dart';        // ✅ Public API
export 'src/s3/s3_options.dart';        // ✅ Public API
export 'src/s3/s3_types.dart';          // ✅ Public API
export 'src/s3/aws_signature_v4.dart';  // ⚠️ Implementation detail (but useful for advanced users)
```

## Issues Found

### 1. FluppyFile - Internal S3-Specific Fields Exposed ⚠️ CRITICAL

**Problem:** `FluppyFile` exposes S3-specific implementation details that shouldn't be part of the public API:

```dart
// These are S3-specific and should be internal:
String? uploadId;                    // ❌ S3 multipart upload ID
String? key;                         // ❌ S3 object key
List<S3Part> uploadedParts = [];    // ❌ S3-specific part tracking
bool isMultipart = false;            // ❌ S3-specific flag
```

**Why this violates Uppy's principles:**

- **Uppy doesn't expose uploader-specific fields** - File objects are generic
- These fields are S3-specific implementation details
- If you add support for other uploaders (Tus, etc.), these fields don't make sense
- Users could accidentally modify these and break upload state
- Violates encapsulation - internal state should be hidden

**Uppy's approach:**

- File objects are generic and don't contain uploader-specific state
- Uploader-specific data is kept in the uploader implementation, not on the file

**Current usage:**

- Used internally by `S3Uploader` and `MultipartUploadController`
- Used in tests (but tests can access internal APIs)
- Used by `Fluppy.resume()` to check upload state

**Recommendation:**

- **Make these fields completely private** (`_uploadId`, `_key`, etc.)
- **Move S3-specific state to an internal extension or mixin** that's not exported
- Use internal accessors only within the `src/` directory
- Consider storing uploader-specific state in a separate internal map keyed by file ID

### 2. FluppyFile - Mutable Status Field ⚠️ CRITICAL

**Problem:** Status is directly mutable, violating Uppy's principle: _"Mutating these properties should be done through methods"_

```dart
FileStatus status;  // ❌ Directly mutable - violates encapsulation
```

**Uppy's approach:**

- Status changes happen through methods, not direct assignment
- File objects are more like value objects with controlled mutations

**Additional problem:** Internal mutation methods are public:

```dart
void updateStatus(FileStatus newStatus, {String? errorMsg, Object? err})  // ❌ Internal
void reset()                                                              // ⚠️ Might be okay
void fullReset()                                                          // ❌ Internal
```

**Current usage:**

- `status` is directly assigned in `Fluppy` class
- `updateStatus()`: Used by `Fluppy` class internally
- `reset()`: Used by `Fluppy.retry()` - might be okay as public
- `fullReset()`: Used by `Fluppy.resume()` internally

**Recommendation:**

- **Make `status` private** (`_status`) with a public getter
- **Make status mutations go through `Fluppy` methods only** - users shouldn't mutate file status directly
- Make `updateStatus()` and `fullReset()` private (prefix with `_`)
- Consider keeping `reset()` public only if it's a documented user-facing operation
- **Status should be read-only from user's perspective** - all mutations happen through Fluppy API

### 3. RetryMixin - Implementation Detail Exported

**Problem:** `RetryMixin` is exported but is an internal implementation detail:

```dart
mixin RetryMixin { ... }  // ⚠️ Exported but internal
```

**Current usage:**

- Used by `S3Uploader` internally
- Could be useful for users creating custom uploaders

**Recommendation:**

- **Option A:** Keep exported if you want to allow users to create custom uploaders with retry logic
- **Option B:** Make it internal if it's only for internal use

**Decision:** Keep exported - it's useful for users creating custom uploaders.

### 4. aws_signature_v4.dart - Implementation Detail Exported

**Problem:** `AwsSignatureV4` is exported but is an implementation detail:

**Current usage:**

- Used internally by `S3Uploader` when using temporary credentials
- Could be useful for advanced users who want to create presigned URLs themselves

**Recommendation:**

- **Option A:** Keep exported - useful for advanced users
- **Option B:** Make internal if you don't want users to use it directly

**Decision:** Keep exported - it's documented and useful for advanced use cases.

## Summary of Recommendations (Based on Uppy Principles)

### Critical Priority (Breaking Changes) 🔴

1. **Make FluppyFile S3-specific fields completely private:**

   ```dart
   // Change from:
   String? uploadId;
   String? key;
   List<S3Part> uploadedParts = [];
   bool isMultipart = false;

   // To:
   String? _uploadId;
   String? _key;
   List<S3Part> _uploadedParts = [];
   bool _isMultipart = false;
   ```

2. **Make status read-only and control mutations through Fluppy:**

   ```dart
   // Change from:
   FileStatus status;  // Directly mutable

   // To:
   FileStatus _status;
   FileStatus get status => _status;  // Read-only getter

   // Status mutations only happen through Fluppy methods:
   // - fluppy.upload() -> sets status to uploading
   // - fluppy.pause() -> sets status to paused
   // - fluppy.cancel() -> sets status to cancelled
   // Users cannot directly mutate status
   ```

3. **Make internal mutation methods private:**

   ```dart
   // Change from:
   void updateStatus(...)
   void fullReset()

   // To:
   void _updateStatus(...)  // Internal only
   void _fullReset()        // Internal only
   ```

4. **Create internal extension for S3-specific state access:**
   ```dart
   // In lib/src/core/fluppy_file.dart (internal, not exported)
   extension S3FileState on FluppyFile {
     // Internal accessors for S3 uploader only
     String? get _s3UploadId => _uploadId;
     void _setS3UploadId(String? value) => _uploadId = value;
     String? get _s3Key => _key;
     void _setS3Key(String? value) => _key = value;
     List<S3Part> get _s3UploadedParts => _uploadedParts;
     bool get _s3IsMultipart => _isMultipart;
     void _setS3IsMultipart(bool value) => _isMultipart = value;
   }
   ```

### High Priority

5. **Consider alternative: Store uploader-specific state separately:**

   ```dart
   // In Fluppy class:
   final Map<String, Map<String, dynamic>> _uploaderState = {};

   // S3 uploader stores its state here:
   _uploaderState[fileId] = {
     'uploadId': '...',
     'key': '...',
     'uploadedParts': [...],
     'isMultipart': true,
   };
   ```

   This approach completely separates file object from uploader state (more aligned with Uppy).

### Medium Priority

6. **Document public API clearly:**
   - Add clear documentation about what's public vs internal
   - Follow Uppy's pattern of documenting file properties
   - Make it clear that status mutations happen through Fluppy methods

### Low Priority

7. **Keep RetryMixin and AwsSignatureV4 exported** - they're useful for advanced users creating custom uploaders

## What Fluppy Does Well ✅

1. **Structured Progress Object** - `UploadProgressInfo` matches Uppy's `progress` object pattern
2. **Event System** - Comprehensive event system similar to Uppy's event-driven architecture
3. **Response Object** - `UploadResponse` matches Uppy's `response` pattern
4. **Metadata Support** - `metadata` field similar to Uppy's `meta` (though Uppy uses `meta`)
5. **Multiple Source Types** - Support for path, bytes, and stream (similar to Uppy's flexibility)
6. **Factory Constructors** - Clean API for creating files from different sources

## Comparison with Uppy's File Object

### Uppy's File Properties (Public API):

```javascript
{
  id: string,              // ✅ Public
  name: string,            // ✅ Public
  type: string,            // ✅ Public
  size: number,            // ✅ Public
  data: File/Blob,         // ✅ Public (local files only)
  source: string,          // ✅ Public (plugin name)
  isRemote: boolean,       // ✅ Public
  meta: object,           // ✅ Public (extensible metadata)
  progress: object,       // ✅ Public (structured progress)
  preview: string?,       // ✅ Public (optional)
  uploadURL: string?,     // ✅ Public (post-upload)
  response: object?,      // ✅ Public (server response)
  remote: object,         // ✅ Public (provider metadata)
  // NO uploader-specific fields!
}
```

### Fluppy's Current File Properties:

```dart
class FluppyFile {
  // ✅ Public (matches Uppy):
  final String id;
  final String name;
  final String? type;
  final int size;
  final FileSourceType sourceType;
  final Map<String, dynamic> metadata;  // Similar to Uppy's meta
  UploadProgressInfo? progress;         // Similar to Uppy's progress
  UploadResponse? response;             // Similar to Uppy's response

  // ⚠️ Problem: Directly mutable (should be read-only)
  FileStatus status;                    // ❌ Should be read-only

  // ❌ Problem: S3-specific (should be internal):
  String? uploadId;                     // Should be private
  String? key;                          // Should be private
  List<S3Part> uploadedParts = [];     // Should be private
  bool isMultipart = false;             // Should be private

  // ❌ Problem: Internal methods exposed:
  void updateStatus(...);                // Should be private
  void fullReset();                      // Should be private
}
```

## Migration Path

### Phase 1: Deprecation (Minor Version)

1. Add `@Deprecated` annotations to public S3-specific fields
2. Add `@Deprecated` annotations to `status` setter (if we add a getter-only property)
3. Add `@Deprecated` annotations to internal methods
4. Add private versions with `_` prefix
5. Add internal extension for S3 state access
6. Update all internal code to use private versions
7. Document migration guide

### Phase 2: Breaking Changes (Major Version)

1. Remove deprecated public fields/methods
2. Make status read-only with getter
3. Ensure all mutations go through Fluppy API
4. Update documentation

## Files That Need Changes

### Core Files:

- `lib/src/core/fluppy_file.dart` - Make fields/methods private, add internal extension
- `lib/src/core/fluppy.dart` - Update to use private fields/methods, control status mutations

### S3 Implementation:

- `lib/src/s3/s3_uploader.dart` - Update to use private fields/methods via internal extension
- `lib/src/s3/multipart_upload_controller.dart` - Update to use private fields/methods

### Tests:

- `test/` - Tests may need updates (can use `@visibleForTesting` or access private members)

## Benefits of These Changes

1. **Better Encapsulation** - Internal state is hidden from users
2. **Uploader Agnostic** - File objects work with any uploader (S3, Tus, etc.)
3. **Controlled Mutations** - Status changes happen through documented API
4. **Uppy Alignment** - Follows proven patterns from Uppy
5. **Future Proof** - Easy to add new uploaders without exposing their internals
6. **Type Safety** - Prevents accidental mutations that break upload state
