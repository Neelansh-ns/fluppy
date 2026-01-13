# API Encapsulation Improvements Implementation Plan

| Field                 | Value                                                                                   |
| --------------------- | --------------------------------------------------------------------------------------- |
| **Created**           | 2025-01-13                                                                              |
| **Last Updated**      | 2025-01-13                                                                              |
| **Uppy Reference**    | [Uppy Core API](https://uppy.io/docs/uppy/)                                             |
| **Status**            | ✅ **COMPLETED**                                                                        |
| **Related Documents** | `docs/review/export-analysis.md`, `docs/research/20250113_uppy-encapsulation-review.md` |

## Overview

This plan implements API encapsulation improvements to align Fluppy's public API with Uppy's design principles. The main goals are:

1. **Hide S3-specific implementation details** ✅ - Made `uploadId`, `key`, `uploadedParts`, and `isMultipart` private via namespaced state
2. **Make status read-only** ✅ - Status mutations now controlled through Fluppy methods only
3. **Hide internal methods** ✅ - Made `updateStatus()` and `fullReset()` private (removed public versions)
4. **Breaking changes implemented** ✅ - Direct implementation without backwards compatibility (as requested)

**Uppy Equivalent**: Uppy's file objects are generic and don't expose uploader-specific fields. Status mutations happen through Uppy methods, not direct property assignment.

## Current State Analysis

### What Exists

- `FluppyFile` class with public S3-specific fields (`uploadId`, `key`, `uploadedParts`, `isMultipart`)
- Public mutable `status` field
- Public internal methods (`updateStatus()`, `fullReset()`, `reset()`)
- Internal code accessing these fields:
  - `lib/src/core/fluppy.dart` - Accesses `status`, `updateStatus()`, `fullReset()`, `uploadedParts`
  - `lib/src/s3/s3_uploader.dart` - Accesses `isMultipart`, `uploadId`, `key`
  - `lib/src/s3/multipart_upload_controller.dart` - Accesses `uploadId`, `key`, `isMultipart`, `uploadedParts`

### What's Missing

- Private fields with `_` prefix
- Internal extension for S3-specific state access
- Read-only status getter
- Deprecation warnings for public fields/methods
- Migration guide

### Key Discoveries

- **54 locations** access these fields across the codebase
- Status is mutated directly in `Fluppy._updateStatus()` (line 490)
- S3-specific fields are accessed in multiple places in S3 uploader and controller
- Tests also access these fields (but can use `@visibleForTesting`)
- **Uppy stores S3 state in `file.s3Multipart` property** (namespaced, not direct fields)
- Uppy uses `uppy.setFileState()` to update uploader-specific state
- This is a better pattern than direct fields - more aligned with Uppy's architecture

## Desired End State

After this plan is complete:

1. **S3-specific fields are private** - Users cannot access `uploadId`, `key`, `uploadedParts`, `isMultipart`
2. **Status is read-only** - Users can read `status` but cannot mutate it directly
3. **Internal methods are private** - `updateStatus()` and `fullReset()` are not accessible to users
4. **Internal code uses extension** - S3 uploader accesses fields via internal extension
5. **Backwards compatible** - Deprecation warnings guide users to new API
6. **Uppy-aligned** - File objects are generic and don't expose uploader-specific state

**Success Criteria:**

- [ ] All S3-specific fields are private
- [ ] Status is read-only from user's perspective
- [ ] Internal methods are private
- [ ] Internal extension provides access for S3 uploader
- [ ] All tests pass
- [ ] Deprecation warnings are in place
- [ ] Migration guide is documented
- [ ] Code follows Dart conventions
- [ ] No linter warnings

## Uppy Alignment

### Uppy's Implementation

Uppy stores uploader-specific state in **namespaced properties** on the file object:

```typescript
// From @uppy/aws-s3/src/index.ts
type MultipartFile<M extends Meta, B extends Body> = UppyFile<M, B> & {
  s3Multipart: UploadResult  // { key: string; uploadId: string }
}

// State is stored via setFileState:
uppy.setFileState(file.id, {
  s3Multipart: {
    key,
    uploadId,
  }
})

// Accessed via type assertion:
...(file as MultipartFile<M, B>).s3Multipart
```

**Key Points:**

- Uploader-specific state is **namespaced** (`s3Multipart`, `tus`, etc.)
- State is stored via `uppy.setFileState()`, not direct property access
- File objects remain generic - uploader state is optional and namespaced
- Status mutations happen through Uppy methods (`upload()`, `pause()`, `cancel()`)

**User's Example:**

```typescript
// Custom metadata stored in file.meta
uppy.setFileMeta(file.id, { ...file.meta, blobId: data.blobId });

// S3 multipart state stored in file.s3Multipart (by Uppy internally)
// Returned from createMultipartUpload callback:
return { uploadId: data.uploadId, key: data.key };
```

### Fluppy Adaptation Strategy

**Option A: Namespaced Property (More Uppy-like)**

- Store S3 state in `file.s3Multipart` property (like Uppy)
- Make it private/internal but accessible via extension
- Keeps file object generic

**Option B: Private Fields + Extension (Current Plan)**

- Store S3 state in private fields (`_uploadId`, `_key`, etc.)
- Access via internal extension
- More Dart-idiomatic but less aligned with Uppy

**Recommendation:** Use **Option A** (namespaced property) to better match Uppy's pattern:

- `file.s3Multipart` contains `{ uploadId, key, uploadedParts, isMultipart }`
- Private/internal but accessible via extension
- More aligned with Uppy's architecture

**API Mapping:**
| Uppy Pattern | Fluppy Pattern | Notes |
|--------------|----------------|-------|
| `file.s3Multipart` property | `file.s3Multipart` (private/internal) | Namespaced state |
| `uppy.setFileState()` | `Fluppy` methods update state | Controlled mutations |
| Method-controlled mutations | `Fluppy` methods control status | `upload()`, `pause()`, `cancel()` |
| Namespaced uploader state | Private `s3Multipart` property | Better alignment with Uppy |

## What We're NOT Doing

- **Not maintaining backwards compatibility** - We're making breaking changes directly
- **Not using deprecation warnings** - Going straight to the better architecture
- **Not changing S3 uploader logic** - Only changing how it accesses fields
- **Not changing event system** - Events remain the same
- **Not changing Uploader interface** - Abstract class stays the same

## Implementation Approach

We'll use a **single-phase approach** with breaking changes:

1. **Phase 1: Direct Implementation** (Breaking Changes) - Remove public S3 fields, make status read-only, use namespaced state

**Rationale**: Since we're making breaking changes anyway, we'll implement the better architecture directly without maintaining backwards compatibility. This results in cleaner code and better alignment with Uppy's design.

---

## Phase 1: Direct Implementation (Breaking Changes) ✅ COMPLETED

### Overview

Implemented the improved architecture directly with breaking changes. Removed public S3-specific fields, made status read-only, and used namespaced state pattern. This is a **breaking change** requiring a major version bump.

**Architecture Review**: After detailed review of Uppy.js codebase (see `docs/research/20250113_uppy-encapsulation-review.md`), confirmed that our implementation correctly matches Uppy's encapsulation pattern:

- ✅ Core never accesses plugin-specific state
- ✅ Plugins manage their own state via extension methods
- ✅ Generic `resetFileState()` method matches Uppy's pattern
- ✅ Complete separation between core and plugins

### Changes Made

1. **Removed deprecated fields/methods**:

   - Removed public `uploadId`, `key`, `uploadedParts`, `isMultipart` fields
   - Removed public `updateStatus()` and `fullReset()` methods
   - Removed `status` setter (status is now read-only)

2. **Made status read-only**:

   - `status` is now a read-only getter
   - Status can only be changed through `Fluppy` methods (`upload()`, `pause()`, `cancel()`, etc.)
   - Internal status updates use `updateStatusInternal()` method (not S3-specific)

3. **Implemented namespaced S3 state**:

   - Created `S3MultipartState` class to hold S3-specific state
   - Added private `_s3Multipart` field on `FluppyFile`
   - Created `S3FileState` extension for internal access
   - All S3 uploader code now uses `file.s3Multipart.uploadId`, `file.s3Multipart.key`, etc.

4. **Fixed core-to-plugin coupling** ✅ **CRITICAL FIX**:

   - **Removed**: Core `Fluppy` accessing `file.s3Multipart.*` directly
   - **Removed**: Core `Fluppy` calling `file.resetS3Multipart()` directly
   - **Added**: Generic `uploader.resetFileState()` method to `Uploader` interface
   - **Implemented**: `S3Uploader.resetFileState()` calls `file.resetS3Multipart()`
   - **Result**: Core is now completely generic and uploader-agnostic ✅

5. **Updated all internal code**:

   - Updated `fluppy.dart` to use generic methods (no S3-specific code)
   - Updated `s3_uploader.dart` to use `file.s3Multipart.*` via extension
   - Updated `multipart_upload_controller.dart` to use `file.s3Multipart.*`
   - Updated all tests to use extension methods

6. **Fixed lint warnings**:
   - Removed unused imports
   - Removed unused variables
   - All tests passing ✅

### Files to Modify

#### 1. `lib/src/core/fluppy_file.dart`

**Changes**:

- Create namespaced `S3MultipartState` class (like Uppy's pattern)
- Store S3 state in private `_s3Multipart` property
- Add private version of status (`_status`)
- Add deprecation annotations to public fields
- Add public getter for status (read-only)
- Add internal extension for S3 state access
- Keep public fields working (delegate to private)

```dart
/// Internal S3 multipart upload state (not exported).
/// Similar to Uppy's `file.s3Multipart` property.
class S3MultipartState {
  String? uploadId;
  String? key;
  List<S3Part> uploadedParts = [];
  bool isMultipart = false;

  S3MultipartState({
    this.uploadId,
    this.key,
    List<S3Part>? uploadedParts,
    this.isMultipart = false,
  }) : uploadedParts = uploadedParts ?? [];

  void reset() {
    uploadId = null;
    key = null;
    uploadedParts.clear();
    isMultipart = false;
  }
}

class FluppyFile {
  // ... existing public fields ...

  // Private S3-specific state (namespaced, like Uppy)
  S3MultipartState? _s3Multipart;

  // Private status
  FileStatus _status;

  /// Current upload status.
  ///
  /// **Deprecated**: Status is now read-only. Use Fluppy methods to change status.
  /// This will be removed in version 2.0.0.
  @Deprecated('Status is now read-only. Use Fluppy methods (upload, pause, cancel) to change status.')
  FileStatus get status => _status;

  @Deprecated('Status is now read-only. Use Fluppy methods to change status.')
  set status(FileStatus value) {
    _status = value;
  }

  // Deprecated S3-specific fields (delegate to _s3Multipart)
  /// The S3 upload ID for multipart uploads.
  ///
  /// **Deprecated**: This field is S3-specific and will be private in version 2.0.0.
  /// Use Fluppy's public API instead.
  @Deprecated('This field is S3-specific and will be private in version 2.0.0')
  String? get uploadId => _s3Multipart?.uploadId;

  @Deprecated('This field is S3-specific and will be private in version 2.0.0')
  set uploadId(String? value) {
    _s3Multipart ??= S3MultipartState();
    _s3Multipart!.uploadId = value;
  }

  // Similar for key, uploadedParts, isMultipart...

  // Internal methods - make private
  void _updateStatus(FileStatus newStatus, {String? errorMsg, Object? err}) {
    _status = newStatus;
    if (newStatus == FileStatus.error) {
      errorMessage = errorMsg;
      error = err;
    }
  }

  void _fullReset() {
    reset();
    _s3Multipart?.reset();
  }

  // Keep updateStatus() public but deprecated for now
  @Deprecated('This method is internal and will be private in version 2.0.0')
  void updateStatus(FileStatus newStatus, {String? errorMsg, Object? err}) {
    _updateStatus(newStatus, errorMsg: errorMsg, err: err);
  }

  @Deprecated('This method is internal and will be private in version 2.0.0')
  void fullReset() {
    _fullReset();
  }
}

// Internal extension for S3 uploader access
extension S3FileState on FluppyFile {
  /// Internal accessors for S3 uploader only.
  /// Not exported - only accessible within lib/src/.
  /// Similar to Uppy's `file.s3Multipart` access pattern.
  S3MultipartState get s3Multipart {
    _s3Multipart ??= S3MultipartState();
    return _s3Multipart!;
  }

  void resetS3Multipart() {
    _s3Multipart?.reset();
  }

  FileStatus get s3Status => _status;
  void setS3Status(FileStatus value) => _status = value;

  void updateS3Status(FileStatus newStatus, {String? errorMsg, Object? err}) {
    _updateStatus(newStatus, errorMsg: errorMsg, err: err);
  }
}
```

**Why**:

- Maintains backwards compatibility
- Provides clear migration path
- Allows internal code to start using private fields
- Follows Dart deprecation best practices

#### 2. `lib/src/core/fluppy.dart`

**Changes**:

- Update `_updateStatus()` to use private `_status` field
- Update status checks to use getter
- Keep using public methods for now (they delegate to private)

```dart
void _updateStatus(FluppyFile file, FileStatus newStatus) {
  final previousStatus = file.status; // Uses getter
  file._status = newStatus; // Direct access to private field (same file)
  _emit(StateChanged(file, previousStatus, newStatus));
}
```

**Why**:

- Prepares for Phase 2 migration
- Status mutations still work through Fluppy methods
- Internal code can access private fields directly

### New Files to Create

#### 1. `docs/migration/v1-to-v2.md`

**Purpose**: Migration guide for users

````markdown
# Migration Guide: v1.x to v2.0

## Breaking Changes

### FluppyFile Status

**Before:**

```dart
file.status = FileStatus.uploading; // Direct mutation
```
````

**After:**

```dart
// Status is read-only - use Fluppy methods
await fluppy.upload(file.id);
```

### S3-Specific Fields

**Before:**

```dart
final uploadId = file.uploadId;
file.uploadId = 'new-id';
```

**After:**

```dart
// These fields are now private
// Use Fluppy's public API instead
// If you need upload state, check file.status and file.progress
```

## Deprecation Warnings

If you see deprecation warnings, update your code to use Fluppy methods instead of direct field access.

````

### Tests to Update

#### 1. `test/fluppy_file_test.dart`

**Changes**: Update tests to handle deprecation warnings

```dart
// Tests can still access deprecated fields, but should be updated
// Use @visibleForTesting if needed for private field access
````

### Success Criteria

- [ ] Code compiles without errors
- [ ] All existing tests pass
- [ ] Deprecation warnings appear when accessing deprecated fields
- [ ] Private fields exist alongside public ones
- [ ] Internal extension is created
- [ ] Migration guide is written
- [ ] Code follows Dart conventions: `dart format`
- [ ] No new linter warnings: `dart analyze`

---

## Phase 2: Internal Code Migration

### Overview

Update all internal code (`lib/src/`) to use private fields and internal extension. This phase is **non-breaking** for users - only internal implementation changes.

### Files to Modify

#### 1. `lib/src/core/fluppy.dart`

**Changes**:

- Update all status mutations to use private `_status` field directly
- Update `_updateStatus()` to use extension methods
- Update status checks to use getter

```dart
// Change from:
file.status = FileStatus.uploading;

// To:
file._status = FileStatus.uploading; // Direct access (same file)

// Or use extension for consistency:
file.setS3Status(FileStatus.uploading);
```

**Why**:

- Prepares for Phase 3 removal of public setters
- Uses private fields directly
- Maintains functionality

#### 2. `lib/src/s3/s3_uploader.dart`

**Changes**:

- Update all S3 field access to use internal extension
- Use `file.s3Multipart.uploadId` instead of `file.uploadId`
- Use namespaced state access pattern (like Uppy)

```dart
// Change from:
if (file.isMultipart && file.uploadId != null) {
  // ...
}

// To:
if (file.s3Multipart.isMultipart && file.s3Multipart.uploadId != null) {
  // ...
}
```

**Why**:

- Uses internal extension (not exported)
- Prepares for Phase 3 removal of public fields
- Maintains functionality

#### 3. `lib/src/s3/multipart_upload_controller.dart`

**Changes**:

- Update all S3 field access to use namespaced state
- Use `file.s3Multipart` property (like Uppy's pattern)

```dart
// Change from:
file.uploadId = result.uploadId;
file.key = result.key;
file.isMultipart = true;
file.uploadedParts.add(part);

// To:
file.s3Multipart.uploadId = result.uploadId;
file.s3Multipart.key = result.key;
file.s3Multipart.isMultipart = true;
file.s3Multipart.uploadedParts.add(part);
```

**Why**:

- Uses internal extension consistently
- Prepares for Phase 3
- Maintains functionality

### Tests to Update

#### 1. `test/fluppy_file_test.dart`

**Changes**:

- Update tests to use public API where possible
- Use `@visibleForTesting` annotation if private field access needed

```dart
// For tests that need to verify internal state:
// Option 1: Test through public API
expect(file.status, equals(FileStatus.uploading));

// Option 2: Use @visibleForTesting if needed
// (Add annotation to FluppyFile if necessary)
```

#### 2. `test/s3_uploader_test.dart`

**Changes**:

- Update tests to use extension methods or public API
- Remove direct field access

```dart
// Change from:
file.uploadId = 'test-id';

// To:
// Use Fluppy methods to set up test state
// Or use extension if testing internal behavior
```

### Success Criteria

- [ ] All internal code uses private fields/extension
- [ ] No direct access to deprecated public fields in `lib/src/`
- [ ] All tests pass
- [ ] Code compiles without errors
- [ ] No linter warnings
- [ ] Public API still works (deprecated but functional)

---

## Phase 3: Breaking Changes (Major Version)

### Overview

Remove deprecated public fields and methods. This is a **breaking change** requiring a major version bump (2.0.0).

### Files to Modify

#### 1. `lib/src/core/fluppy_file.dart`

**Changes**:

- Remove deprecated public fields (`uploadId`, `key`, `uploadedParts`, `isMultipart`)
- Remove deprecated public setters
- Remove deprecated methods (`updateStatus()`, `fullReset()`)
- Keep only private `_s3Multipart` state and internal extension
- Make status getter-only (no setter)

```dart
class FluppyFile {
  // ... existing public fields ...

  // Private S3-specific state (namespaced, like Uppy)
  S3MultipartState? _s3Multipart;

  // Private status
  FileStatus _status;

  /// Current upload status (read-only).
  ///
  /// Status can only be changed through Fluppy methods:
  /// - [Fluppy.upload] - sets status to uploading
  /// - [Fluppy.pause] - sets status to paused
  /// - [Fluppy.cancel] - sets status to cancelled
  FileStatus get status => _status;

  // No public setters or deprecated fields

  // Private internal methods
  void _updateStatus(FileStatus newStatus, {String? errorMsg, Object? err}) {
    _status = newStatus;
    if (newStatus == FileStatus.error) {
      errorMessage = errorMsg;
      error = err;
    }
  }

  void _fullReset() {
    reset();
    _s3Multipart?.reset();
  }

  // Public reset() method (if we decide to keep it)
  void reset() {
    _status = FileStatus.pending;
    progress = null;
    errorMessage = null;
    error = null;
    response = null;
    // Keep multipart state for resume capability
  }
}

// Internal extension (not exported)
extension S3FileState on FluppyFile {
  /// Internal accessors for S3 uploader only.
  /// Similar to Uppy's `file.s3Multipart` access pattern.
  S3MultipartState get s3Multipart {
    _s3Multipart ??= S3MultipartState();
    return _s3Multipart!;
  }

  void resetS3Multipart() {
    _s3Multipart?.reset();
  }

  FileStatus get s3Status => _status;
  void setS3Status(FileStatus value) => _status = value;

  void updateS3Status(FileStatus newStatus, {String? errorMsg, Object? err}) {
    _updateStatus(newStatus, errorMsg: errorMsg, err: err);
  }
}
```

**Why**:

- Removes deprecated API
- Makes status truly read-only
- Hides S3-specific implementation details
- Aligns with Uppy's design

#### 2. `lib/src/core/fluppy.dart`

**Changes**:

- Ensure all status mutations use private field directly
- Update any remaining public field access

```dart
void _updateStatus(FluppyFile file, FileStatus newStatus) {
  final previousStatus = file._status; // Direct access
  file._status = newStatus; // Direct mutation
  _emit(StateChanged(file, previousStatus, newStatus));
}
```

**Why**:

- Uses private fields exclusively
- No public API for status mutation

#### 3. `CHANGELOG.md`

**Changes**:

- Document breaking changes
- List removed fields/methods
- Provide migration examples

```markdown
## 2.0.0 (Breaking Changes)

### Removed

- `FluppyFile.uploadId` - Use Fluppy's public API instead
- `FluppyFile.key` - Use Fluppy's public API instead
- `FluppyFile.uploadedParts` - Use Fluppy's public API instead
- `FluppyFile.isMultipart` - Use Fluppy's public API instead
- `FluppyFile.status` setter - Use Fluppy methods (upload, pause, cancel)
- `FluppyFile.updateStatus()` - Internal method, use Fluppy methods
- `FluppyFile.fullReset()` - Internal method, use Fluppy.retry() or Fluppy.resume()

### Changed

- `FluppyFile.status` is now read-only - mutations happen through Fluppy methods
```

### Tests to Update

#### 1. All test files

**Changes**:

- Remove all direct field mutations
- Use Fluppy methods for status changes
- Use public API for assertions

```dart
// Change from:
file.status = FileStatus.uploading;

// To:
await fluppy.upload(file.id);
expect(file.status, equals(FileStatus.uploading));
```

### Success Criteria

- [x] All deprecated fields/methods removed ✅
- [x] Status is read-only (no public setter) ✅
- [x] All tests pass ✅
- [x] Code compiles without errors ✅
- [x] Core doesn't access plugin-specific state ✅ **CRITICAL**
- [x] Plugins manage their own state ✅
- [x] Architecture matches Uppy's pattern ✅
- [ ] Migration guide is complete (TODO)
- [ ] CHANGELOG.md updated (TODO)
- [ ] Version bumped to 2.0.0 (TODO)
- [x] No linter warnings ✅

### Architecture Validation

After reviewing Uppy.js source code, confirmed our implementation matches Uppy's encapsulation pattern:

**Uppy Pattern**:

- Core never accesses `file.s3Multipart` directly
- Plugins use `uppy.setFileState()` to manage state
- Core uses generic methods, plugins handle specifics

**Fluppy Implementation**:

- ✅ Core never accesses `file.s3Multipart` directly
- ✅ Plugins use extension methods to manage state
- ✅ Core uses generic `uploader.resetFileState()` method
- ✅ Complete separation achieved

**See**: `docs/research/20250113_uppy-encapsulation-review.md` for detailed analysis

---

## Testing Strategy

### Unit Tests

- **FluppyFile tests**: Verify status is read-only, S3 fields are private
- **Fluppy tests**: Verify status mutations work through Fluppy methods
- **S3Uploader tests**: Verify extension methods work correctly

### Integration Tests

- **End-to-end upload**: Verify status changes correctly through upload lifecycle
- **Pause/resume**: Verify status changes through pause/resume
- **Error handling**: Verify status changes on errors

### Manual Testing

- **Deprecation warnings**: Verify warnings appear in IDE
- **Migration**: Test migration guide examples
- **Backwards compatibility**: Verify Phase 1 doesn't break existing code

## Documentation Updates

### API Documentation

- [ ] Update `FluppyFile` dartdoc - document read-only status
- [ ] Update `Fluppy` dartdoc - emphasize status control
- [ ] Add examples showing proper usage
- [ ] Document internal extension (for contributors)

### Migration Documentation

- [ ] Create `docs/migration/v1-to-v2.md`
- [ ] Update README with breaking changes notice
- [ ] Add deprecation notices to public API docs

### Alignment Documentation

- [ ] Update `docs/review/export-analysis.md` with completion status
- [ ] Document any deviations from Uppy (if any)

## Migration Guide

### For Users

**Before (v1.x):**

```dart
final file = fluppy.addFile(FluppyFile.fromPath('/path/to/file'));
file.status = FileStatus.uploading; // ❌ Direct mutation
final uploadId = file.uploadId; // ❌ S3-specific field
```

**After (v2.0):**

```dart
final file = fluppy.addFile(FluppyFile.fromPath('/path/to/file'));
await fluppy.upload(file.id); // ✅ Use Fluppy methods
final status = file.status; // ✅ Read-only
// uploadId is private - use Fluppy's public API instead
```

### For Contributors

**Internal code should use:**

- `file._status` for direct access (same file)
- `file.s3UploadId` via extension (S3 uploader)
- `file.setS3Status()` via extension (S3 uploader)

**Never expose:**

- Direct field mutations to users
- S3-specific fields in public API

## References

- **Uppy Documentation**: https://uppy.io/docs/uppy/
- **Uppy File Object**: https://uppy.io/docs/uppy/#working-with-uppy-files
- **Export Analysis**: `docs/review/export-analysis.md`
- **Uppy Architecture Review**: `docs/research/20250113_uppy-encapsulation-review.md`
- **Dart Deprecation**: https://dart.dev/guides/language/effective-dart/documentation#deprecation

---

## Post-Implementation Architecture Review

### Uppy.js Source Code Analysis

After detailed review of Uppy.js source code (see `docs/research/20250113_uppy-encapsulation-review.md`), confirmed that Fluppy's implementation correctly matches Uppy's encapsulation pattern.

**Key Findings from Uppy Review**:

1. **Core Never Accesses Plugin State** ✅

   - Uppy core (`Uppy.ts`) never accesses `file.s3Multipart` directly
   - Core methods are completely generic
   - **Fluppy Status**: ✅ Fixed - Core uses generic `uploader.resetFileState()`

2. **Plugins Manage Own State** ✅

   - Plugins use `uppy.setFileState()` to store plugin-specific state
   - Core doesn't know what properties are being set
   - **Fluppy Status**: ✅ Correct - S3 uploader uses extension methods

3. **Type-Level Namespacing** ✅

   - TypeScript uses intersection types: `UppyFile & { s3Multipart: ... }`
   - Runtime: Just JavaScript objects with properties
   - **Fluppy Status**: ✅ Correct - Dart uses private fields + extensions

4. **State Reset Pattern** ✅
   - Each plugin handles its own state cleanup
   - Core doesn't know about plugin-specific cleanup
   - **Fluppy Status**: ✅ Correct - `uploader.resetFileState()` pattern matches

**Architecture Validation**: ✅ **PASSED**

Fluppy's architecture now correctly matches Uppy's pattern:

- Core is generic and uploader-agnostic
- Plugins manage their own state
- No coupling between core and specific uploaders
- Complete separation of concerns achieved

### Minor Recommendations (Optional)

1. **Move Generic Types**: Consider moving `CancellationToken`, `UploadProgressInfo`, `UploadResponse` to `lib/src/core/types.dart`

   - **Priority**: Medium
   - **Rationale**: These are used by all uploaders, not S3-specific

2. **Extension Location**: Consider moving `S3FileState` extension to `lib/src/s3/fluppy_file_extension.dart`
   - **Priority**: Low
   - **Rationale**: Current location works, but moving would improve module boundaries

**Status**: Architecture is correct. Minor improvements are optional and don't affect functionality.

## Open Questions

None - all decisions made based on Uppy alignment and Dart best practices.

---

## Post-Implementation Review

### Uppy Architecture Review

After detailed review of Uppy.js source code (see `docs/research/20250113_uppy-encapsulation-review.md`), confirmed:

**Key Findings**:

1. ✅ **Core never accesses plugin state**: Uppy core never accesses `file.s3Multipart` directly
2. ✅ **Plugins manage own state**: Plugins use `uppy.setFileState()` to store plugin-specific state
3. ✅ **Generic reset pattern**: Each plugin handles its own state cleanup
4. ✅ **Type-level namespacing**: TypeScript intersection types provide type safety without runtime coupling

**Fluppy Alignment**:

- ✅ Core doesn't access `file.s3Multipart.*` (fixed)
- ✅ Core uses generic `uploader.resetFileState()` method (matches Uppy)
- ✅ S3 uploader manages its own state via extension (matches Uppy)
- ✅ Complete separation achieved

### Minor Improvements (Optional)

1. **Move generic types to core**: `CancellationToken`, `UploadProgressInfo`, `UploadResponse` should be in `lib/src/core/types.dart` instead of `lib/src/s3/s3_types.dart`

   - **Priority**: Medium
   - **Rationale**: These types are used by all uploaders, not S3-specific

2. **Consider moving extension**: `S3FileState` extension could be moved to `lib/src/s3/fluppy_file_extension.dart` for better separation
   - **Priority**: Low
   - **Rationale**: Current location works fine, but moving would improve module boundaries

**Status**: Architecture is correct and matches Uppy's pattern. Minor improvements are optional.

---

## Implementation Notes

### Extension Naming

The internal extension uses `s3` prefix (e.g., `s3UploadId`) to make it clear these are S3-specific accessors. This helps distinguish from generic file properties.

### Status Mutations

All status mutations go through `Fluppy._updateStatus()` which:

1. Updates private `_status` field
2. Emits `StateChanged` event
3. Ensures consistency

### Backwards Compatibility

Phase 1 maintains full backwards compatibility while preparing for breaking changes. Users can migrate gradually.

### Testing Strategy

Tests can use `@visibleForTesting` annotation if needed for private field access, but should prefer testing through public API.
