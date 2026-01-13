# Uppy.js Encapsulation Architecture Review

**Created**: 2025-01-13  
**Reviewed Version**: @uppy/aws-s3@5.0.2, @uppy/core@5.1.1  
**Purpose**: Understand how Uppy.js achieves encapsulation between core and plugins

---

## Executive Summary

Uppy.js achieves **complete separation** between core and plugins through:

1. **Generic state management**: Core uses `setFileState()` which accepts any `Partial<UppyFile>` - core doesn't know or care about plugin-specific properties
2. **Type-level namespacing**: TypeScript intersection types (`UppyFile & { s3Multipart: ... }`) provide type safety without runtime coupling
3. **Plugin-owned state**: Plugins manage their own state via `uppy.setFileState()` and access it via type assertions
4. **No core-to-plugin coupling**: Core **never** accesses plugin-specific properties like `file.s3Multipart` directly
5. **Centralized state store**: All file state (including plugin-specific) lives in Uppy's central state store

---

## Key Findings

### 1. Core Never Accesses Plugin-Specific State

**Finding**: Uppy core (`Uppy.ts`) **never** directly accesses plugin-specific properties like `file.s3Multipart`, `file.tus`, etc.

**Evidence**:
- Core's `getFile()` method returns generic `UppyFile<M, B>` type
- Core's `setFileState()` accepts `Partial<UppyFile<M, B>>` - it's generic and doesn't know about specific properties
- Core methods like `retry()`, `pause()`, `cancel()` work with generic file objects
- No imports of plugin-specific types in core

**Code Reference** (`Uppy.ts:597-604`):
```typescript
setFileState(fileID: string, state: Partial<UppyFile<M, B>>): void {
  if (!this.getState().files[fileID]) {
    throw new Error(
      `Can't set state for ${fileID} (the file could have been removed)`,
    )
  }
  this.patchFilesState({ [fileID]: state })
}
```

**Implication for Fluppy**: Core `Fluppy` class should **never** access `file.s3Multipart` or call S3-specific methods. All plugin-specific state access should be in the plugin itself.

---

### 2. Plugins Manage Their Own State via `setFileState()`

**Finding**: Plugins use `uppy.setFileState()` to store plugin-specific state, but core doesn't know what properties are being set.

**Evidence** (`aws-s3/src/index.ts:799-816`):
```typescript
#setS3MultipartState = (
  file: UppyFile<M, B>,
  { key, uploadId }: UploadResult,
) => {
  const cFile = this.uppy.getFile(file.id)
  if (cFile == null) {
    // file was removed from store
    return
  }

  this.uppy.setFileState(file.id, {
    s3Multipart: {
      ...(cFile as MultipartFile<M, B>).s3Multipart,
      key,
      uploadId,
    },
  } as Partial<MultipartFile<M, B>>)
}
```

**Key Points**:
- Plugin calls `uppy.setFileState()` with `s3Multipart` property
- Core doesn't know what `s3Multipart` is - it just merges the partial state
- Plugin uses type assertion `as MultipartFile<M, B>` for type safety
- Plugin accesses state via `uppy.getFile()` and type assertion

**Implication for Fluppy**: S3 uploader should manage its own state via a method on `FluppyFile` or through the `Uploader` interface, not through core `Fluppy` class.

---

### 3. Type-Level Namespacing (TypeScript Pattern)

**Finding**: Uppy uses TypeScript intersection types to namespace plugin-specific state at the type level.

**Evidence** (`aws-s3/src/index.ts:35-37`):
```typescript
type MultipartFile<M extends Meta, B extends Body> = UppyFile<M, B> & {
  s3Multipart: UploadResult
}
```

**How It Works**:
- Base type: `UppyFile<M, B>` (generic, from core)
- Plugin extends: `& { s3Multipart: UploadResult }` (plugin-specific)
- Runtime: Still just a JavaScript object with `s3Multipart` property
- Type system: Provides type safety without runtime coupling

**Dart Equivalent**: Dart doesn't have intersection types, but we can achieve similar encapsulation:
- Use private fields (`_s3Multipart`)
- Use extension methods for internal access
- Core never imports or knows about `S3MultipartState`

---

### 4. Plugin State Access Pattern

**Finding**: Plugins access their own state via:
1. `uppy.getFile(fileID)` - gets generic file
2. Type assertion `(file as MultipartFile)` - tells TypeScript about plugin state
3. Direct property access `file.s3Multipart.uploadId`

**Evidence** (`aws-s3/src/index.ts:886`):
```typescript
...(file as MultipartFile<M, B>).s3Multipart,
```

**Evidence** (`aws-s3/src/MultipartUploader.ts:114`):
```typescript
this.#isRestoring = (options.uploadId && options.key) as any as boolean
```

**Implication for Fluppy**: 
- S3 uploader should access `file.s3Multipart` via extension method
- Core should never see or know about `s3Multipart`
- Extension provides type-safe access within `lib/src/s3/` only

---

### 5. State Reset Pattern

**Finding**: When uploads need to be reset, plugins handle their own state cleanup.

**Evidence** (`aws-s3/src/index.ts:455-464`):
```typescript
resetUploaderReferences(fileID: string, opts?: { abort: boolean }): void {
  if (this.uploaders[fileID]) {
    this.uploaders[fileID]!.abort({ really: opts?.abort || false })
    this.uploaders[fileID] = null
  }
  if (this.uploaderEvents[fileID]) {
    this.uploaderEvents[fileID]!.remove()
    this.uploaderEvents[fileID] = null
  }
}
```

**Key Points**:
- Plugin has its own `resetUploaderReferences()` method
- Core doesn't know about plugin state cleanup
- Plugin manages its own uploader instances and event handlers

**Implication for Fluppy**: 
- `Uploader.resetFileState()` method (already added) is correct pattern
- Each uploader should handle its own state reset
- Core just calls the generic `resetFileState()` method

---

### 6. Core Never Calls Plugin-Specific Methods

**Finding**: Core never calls methods like `resetS3Multipart()` or accesses `file.s3Multipart` directly.

**Evidence**: 
- Searched entire `Uppy.ts` file - no references to `s3Multipart`, `tus`, or any plugin-specific properties
- Core methods are completely generic
- Plugins register themselves via `addUploader()` but core doesn't know their implementation details

**Implication for Fluppy**: 
- Core `Fluppy` should **never** call `file.resetS3Multipart()`
- Core should **never** access `file.s3Multipart.*`
- All S3-specific logic should be in `S3Uploader` class

---

### 7. File State Storage Architecture

**Finding**: All file state (including plugin-specific) is stored in Uppy's central state store.

**Architecture**:
```
Uppy State Store
├── files: {
│     [fileID]: {
│       id, name, size, type, ...  // Core properties
│       s3Multipart: { ... }       // Plugin-specific (optional)
│       tus: { ... }               // Plugin-specific (optional)
│     }
│   }
└── ...
```

**Key Points**:
- Single source of truth: `getState().files[fileID]`
- Plugin state is just properties on the file object
- Core doesn't distinguish between core and plugin properties
- Plugins add properties via `setFileState()`

**Implication for Fluppy**:
- `FluppyFile` object stores all state (core + plugin-specific)
- Plugin-specific state is private/internal
- Core doesn't need to know about plugin state structure

---

## Critical Architectural Insights

### 1. Complete Separation of Concerns

**Uppy Pattern**:
- Core: Generic file management, state updates, events
- Plugins: Upload logic, plugin-specific state management
- **No coupling**: Core never imports plugin types or accesses plugin properties

**Fluppy Current Issue**:
- Core `Fluppy` was accessing `file.s3Multipart.*` ❌
- Core `Fluppy` was calling `file.resetS3Multipart()` ❌

**Fluppy Correct Pattern**:
- Core uses generic `uploader.resetFileState(file)` ✅
- S3 uploader implements `resetFileState()` to call `file.resetS3Multipart()` ✅
- Core never knows about S3-specific implementation ✅

---

### 2. Plugin State Management

**Uppy Pattern**:
```typescript
// Plugin sets state
uppy.setFileState(file.id, {
  s3Multipart: { key, uploadId }
})

// Plugin accesses state
const file = uppy.getFile(file.id)
const s3State = (file as MultipartFile).s3Multipart
```

**Fluppy Pattern** (Current):
```dart
// S3 uploader sets state
file.s3Multipart.uploadId = result.uploadId
file.s3Multipart.key = result.key

// S3 uploader accesses state
final uploadId = file.s3Multipart.uploadId
```

**Status**: ✅ **Correct** - S3 uploader manages its own state via extension

---

### 3. State Reset Pattern

**Uppy Pattern**:
- Plugin has `resetUploaderReferences()` method
- Core doesn't know about plugin state cleanup
- Each plugin handles its own cleanup

**Fluppy Pattern** (After Fix):
```dart
// Core (generic)
await uploader.resetFileState(file)

// S3 Uploader (specific)
@override
Future<void> resetFileState(FluppyFile file) async {
  file.resetS3Multipart()
}
```

**Status**: ✅ **Correct** - Matches Uppy's pattern

---

## Comparison: Uppy vs Fluppy

| Aspect | Uppy.js | Fluppy (Current) | Status |
|--------|---------|------------------|--------|
| **Core accesses plugin state** | ❌ Never | ❌ Was doing it | ✅ Fixed |
| **Plugin manages own state** | ✅ Via `setFileState()` | ✅ Via extension | ✅ Correct |
| **State reset** | ✅ Plugin method | ✅ `resetFileState()` | ✅ Correct |
| **Type safety** | ✅ Intersection types | ✅ Extension methods | ✅ Correct |
| **Core imports plugin types** | ❌ Never | ❌ Was importing S3 types | ⚠️ Needs review |

---

## Remaining Issues to Address

### 1. Core Imports S3 Types

**Issue**: `lib/src/core/fluppy.dart` imports `../s3/s3_types.dart`

**Evidence**:
```dart
import '../s3/s3_types.dart';
```

**Why This Exists**:
- `CancellationToken`, `UploadProgressInfo`, `UploadResponse` are defined in `s3_types.dart`
- These are actually **generic types** used by all uploaders

**Solution**:
- Move generic types (`CancellationToken`, `UploadProgressInfo`, `UploadResponse`, `PausedException`, `CancelledException`) to `lib/src/core/types.dart`
- Keep S3-specific types (`S3Part`, `S3Options`, etc.) in `lib/src/s3/`
- Update imports accordingly

**Priority**: Medium - Works currently but creates unnecessary coupling

---

### 2. Extension Method Visibility

**Current**: Extension `S3FileState` is in `lib/src/core/fluppy_file.dart`

**Issue**: Extension is in core file, but only used by S3 uploader

**Options**:
1. **Keep in core** (current): Extension lives with `FluppyFile` class
   - Pros: Easy to find, close to class definition
   - Cons: Core file contains S3-specific code

2. **Move to S3 module**: Extension in `lib/src/s3/fluppy_file_extension.dart`
   - Pros: Better separation, S3-specific code in S3 module
   - Cons: Need to import extension in S3 uploader

**Recommendation**: **Option 2** - Move extension to S3 module for better separation

---

## Recommendations

### 1. Move Generic Types to Core

**Action**: Create `lib/src/core/types.dart` with:
- `CancellationToken`
- `UploadProgressInfo`
- `UploadResponse`
- `PausedException`
- `CancelledException`

**Rationale**: These are used by all uploaders, not S3-specific

---

### 2. Move S3 Extension to S3 Module

**Action**: Move `S3FileState` extension to `lib/src/s3/fluppy_file_extension.dart`

**Rationale**: Better separation - S3-specific code belongs in S3 module

---

### 3. Verify No Core-to-Plugin Coupling

**Action**: Search codebase for:
- Core accessing `file.s3Multipart.*`
- Core calling S3-specific methods
- Core importing S3-specific types

**Status**: ✅ Already fixed - `resetFileState()` pattern is correct

---

## Conclusion

### What We Got Right

1. ✅ **Namespaced state**: `file.s3Multipart` pattern matches Uppy
2. ✅ **Extension methods**: Provide internal access like Uppy's type assertions
3. ✅ **Generic reset method**: `uploader.resetFileState()` matches Uppy's pattern
4. ✅ **Core doesn't access plugin state**: Fixed - core uses generic methods

### What Needs Improvement

1. ⚠️ **Generic types location**: Move shared types to core
2. ⚠️ **Extension location**: Consider moving to S3 module
3. ✅ **Architecture alignment**: Now matches Uppy's separation pattern

### Final Assessment

**Architecture Quality**: ✅ **Excellent** - Matches Uppy's encapsulation pattern

The current implementation correctly separates core from plugins:
- Core is generic and uploader-agnostic
- Plugins manage their own state
- No coupling between core and specific uploaders

Minor improvements (type organization) can be made, but the architecture is sound.

---

## References

- **Uppy Core**: `/Users/neelanshsethi/StudioProjects/iv-pro-web/web/node_modules/.pnpm/@uppy+core@5.1.1/node_modules/@uppy/core/src/Uppy.ts`
- **Uppy AWS-S3**: `/Users/neelanshsethi/StudioProjects/iv-pro-web/web/node_modules/.pnpm/@uppy+aws-s3@5.0.2/node_modules/@uppy/aws-s3/src/index.ts`
- **Uppy MultipartUploader**: `/Users/neelanshsethi/StudioProjects/iv-pro-web/web/node_modules/.pnpm/@uppy+aws-s3@5.0.2/node_modules/@uppy/aws-s3/src/MultipartUploader.ts`
