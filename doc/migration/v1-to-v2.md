# Migration Guide: v1.x to v2.0

This guide helps you migrate your code from Fluppy v1.x to v2.0, which introduces API encapsulation improvements to align with Uppy's design principles.

## Overview

Fluppy v2.0 makes the following changes to improve API encapsulation:

1. **S3-specific fields are now private** - `uploadId`, `key`, `uploadedParts`, and `isMultipart` are no longer accessible
2. **Status is read-only** - You can read `status` but cannot mutate it directly
3. **Internal methods are private** - `updateStatus()` and `fullReset()` are no longer accessible

These changes ensure that:
- File objects remain generic and uploader-agnostic
- Status mutations happen through Fluppy's documented API
- Internal implementation details are hidden from users

## Breaking Changes

### FluppyFile Status

**Before (v1.x):**
```dart
final file = fluppy.addFile(FluppyFile.fromPath('/path/to/file'));
file.status = FileStatus.uploading; // ❌ Direct mutation
```

**After (v2.0):**
```dart
final file = fluppy.addFile(FluppyFile.fromPath('/path/to/file'));
await fluppy.upload(file.id); // ✅ Use Fluppy methods
// Status is read-only - you can read it but not change it directly
final currentStatus = file.status; // ✅ Reading is fine
```

### S3-Specific Fields

**Before (v1.x):**
```dart
final uploadId = file.uploadId; // ❌ Direct access
file.uploadId = 'new-id'; // ❌ Direct mutation
final key = file.key;
final parts = file.uploadedParts;
final isMultipart = file.isMultipart;
```

**After (v2.0):**
```dart
// These fields are now private
// Use Fluppy's public API instead
// If you need upload state, check file.status and file.progress

// For S3 callbacks, uploadId and key are passed as parameters:
completeMultipartUpload: (file, options) async {
  final uploadId = options.uploadId; // ✅ From options parameter
  final key = options.key;           // ✅ From options parameter
  final parts = options.parts;
  
  // Your implementation...
}
```

### Internal Methods

**Before (v1.x):**
```dart
file.updateStatus(FileStatus.error, errorMsg: 'Error');
file.fullReset();
```

**After (v2.0):**
```dart
// These methods are now private
// Use Fluppy methods instead:
await fluppy.retry(file.id); // ✅ Retry failed uploads
// Or let Fluppy handle status changes automatically
```

## Migration Steps

### Step 1: Update Status Mutations

Find all places where you directly set `file.status`:

```dart
// ❌ Old way
file.status = FileStatus.uploading;

// ✅ New way
await fluppy.upload(file.id);
```

### Step 2: Remove S3 Field Access

If you're accessing S3-specific fields directly, remove those accesses:

```dart
// ❌ Old way
if (file.isMultipart && file.uploadId != null) {
  // ...
}

// ✅ New way
// These fields are no longer accessible
// Use file.status and file.progress instead
if (file.status == FileStatus.paused) {
  await fluppy.resume(file.id);
}
```

### Step 3: Update S3 Callbacks

Your S3 callbacks already receive `uploadId` and `key` as parameters, so no changes needed:

```dart
// ✅ This already works correctly
completeMultipartUpload: (file, options) async {
  final uploadId = options.uploadId; // From options
  final key = options.key;             // From options
  // ... your implementation
}
```

### Step 4: Use Fluppy Methods for Status Changes

Replace direct status mutations with Fluppy methods:

| Old Way | New Way |
|---------|---------|
| `file.status = FileStatus.uploading` | `await fluppy.upload(file.id)` |
| `file.status = FileStatus.paused` | `await fluppy.pause(file.id)` |
| `file.status = FileStatus.cancelled` | `await fluppy.cancel(file.id)` |
| `file.updateStatus(...)` | Let Fluppy handle it automatically |

## Deprecation Warnings

If you see deprecation warnings in v1.x, update your code to use Fluppy methods instead of direct field access. The warnings will guide you to the correct API.

## Benefits

After migrating to v2.0:

- ✅ **Better encapsulation** - Internal state is hidden
- ✅ **Uploader agnostic** - File objects work with any uploader (S3, Tus, etc.)
- ✅ **Controlled mutations** - Status changes happen through documented API
- ✅ **Uppy alignment** - Follows proven patterns from Uppy
- ✅ **Future proof** - Easy to add new uploaders without exposing internals

## Questions?

If you encounter issues during migration, please:
1. Check this guide
2. Review the [API documentation](../README.md)
3. Open an issue on GitHub
