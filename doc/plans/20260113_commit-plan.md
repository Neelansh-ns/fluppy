# Commit Plan for API Encapsulation Changes

| Field       | Value      |
| ----------- | ---------- |
| **Created** | 2026-01-13 |
| **Status**  | Planning   |

## Overview

This document outlines a structured approach to committing the API encapsulation improvements. The changes implement better encapsulation by making status read-only, hiding S3-specific implementation details, and aligning with Uppy's architecture patterns.

**Total Changes**: 21 files modified, 4 new files, 244 insertions(+), 384 deletions(-)

---

## Commit Strategy

We'll organize commits into **logical feature sections**, where each section represents a cohesive set of changes. Each section can have multiple smaller commits for better granularity.

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**: `feat`, `refactor`, `test`, `docs`, `chore`
**Scopes**: `core`, `s3`, `test`, `docs`, `example`

---

## Section 1: Core Types Extraction

**Goal**: Extract generic types used by all uploaders into a shared core types file.

### Commit 1.1: Extract core types to shared module

**Files**:

- `lib/src/core/types.dart` (NEW)
- `lib/src/s3/s3_types.dart` (modified - remove generic types)
- `lib/src/core/uploader.dart` (modified - import types)
- `lib/src/s3/s3_uploader.dart` (modified - import types)

**Message**:

```
refactor(core): extract generic types to core/types.dart

Move CancellationToken, UploadProgressInfo, UploadResponse, and
exception types from s3_types.dart to a new core/types.dart module.
These types are used by all uploaders, not just S3.

This improves code organization and makes it easier to add new
uploaders without duplicating type definitions.
```

---

## Section 2: S3 State Management Extensions

**Goal**: Implement namespaced S3 state using extensions, following Uppy's pattern.

### Commit 2.1: Add S3 file extension infrastructure

**Files**:

- `lib/src/s3/fluppy_file_extension.dart` (NEW)
- `lib/src/s3/fluppy_file_extension_public.dart` (NEW)
- `lib/src/s3/s3_types.dart` (modified - add S3MultipartState)

**Message**:

```
feat(s3): add S3 file extension for namespaced state management

Create extension methods for S3-specific state management using
Expando for private storage. This follows Uppy's pattern of
namespaced plugin state (file.s3Multipart).

- Add internal S3FileState extension for uploader access
- Add public S3FilePublic extension for read-only user access
- Use Expando to store state without modifying FluppyFile class
- Add S3MultipartState class to hold S3-specific state
```

### Commit 2.2: Add S3-specific events

**Files**:

- `lib/src/s3/s3_events.dart` (NEW)
- `lib/src/core/events.dart` (modified - ensure compatibility)

**Message**:

```
feat(s3): add S3-specific events

Add S3PartUploaded event for tracking multipart upload progress.
This allows users to listen to part-level upload events while
keeping core events generic and uploader-agnostic.
```

---

## Section 3: Core API Encapsulation

**Goal**: Make status read-only and remove S3-specific fields from public API.

### Commit 3.1: Refactor FluppyFile to part file and make status read-only

**Files**:

- `lib/src/core/fluppy.dart` (modified - add library directive, move imports)
- `lib/src/core/fluppy_file.dart` (modified - convert to part file, status read-only)

**Message**:

```
refactor(core): convert FluppyFile to part file and make status read-only

Convert FluppyFile to a part of fluppy.dart to improve code
organization. Make status read-only by changing from public field
to private _status with public getter.

Status can now only be changed through Fluppy methods (upload,
pause, cancel, retry). This improves encapsulation and prevents
users from directly mutating file state.

Breaking change: Status setter removed. Users must use Fluppy
methods to change file status.
```

### Commit 3.2: Remove S3-specific fields from FluppyFile public API

**Files**:

- `lib/src/core/fluppy_file.dart` (modified - remove public S3 fields)
- `lib/src/core/fluppy.dart` (modified - remove S3-specific code)
- `lib/src/s3/s3_uploader.dart` (modified - use extension)
- `lib/src/s3/multipart_upload_controller.dart` (modified - use extension)

**Message**:

```
refactor(core): remove S3-specific fields from FluppyFile public API

Remove uploadId, key, uploadedParts, and isMultipart from public
API. These are now accessed via S3FileState extension internally
and S3FilePublic extension for read-only user access.

Remove core's direct access to S3-specific state. Core now uses
generic uploader.resetFileState() method instead of accessing
file.uploadedParts directly.

This aligns with Uppy's pattern where file objects are generic
and uploader-specific state is namespaced.

Breaking change: S3-specific fields are no longer directly
accessible. Use S3FilePublic extension for read-only access.
```

### Commit 3.3: Add generic resetFileState to Uploader interface

**Files**:

- `lib/src/core/uploader.dart` (modified - add resetFileState)
- `lib/src/core/fluppy.dart` (modified - use generic reset)
- `lib/src/s3/s3_uploader.dart` (modified - implement resetFileState)

**Message**:

```
refactor(core): add generic resetFileState to Uploader interface

Add resetFileState() method to Uploader abstract class to allow
core to reset uploader-specific state without knowing implementation
details. This removes coupling between core and S3 uploader.

S3Uploader implements resetFileState() to reset S3 multipart state.
This follows Uppy's pattern where core is generic and plugins
manage their own state cleanup.
```

---

## Section 4: S3 Implementation Updates

**Goal**: Update S3 uploader and controller to use new extension-based state management.

### Commit 4.1: Update S3 uploader to use extension methods

**Files**:

- `lib/src/s3/s3_uploader.dart` (modified - use s3Multipart extension)
- `lib/src/s3/multipart_upload_controller.dart` (modified - use extension)
- `lib/src/s3/aws_signature_v4.dart` (modified - if needed)

**Message**:

```
refactor(s3): update S3 uploader to use extension-based state

Replace direct field access (file.uploadId, file.key) with
extension methods (file.s3Multipart.uploadId, file.s3Multipart.key).
This uses the new namespaced state pattern.

All S3-specific state access now goes through S3FileState extension,
keeping FluppyFile generic and uploader-agnostic.
```

### Commit 4.2: Update S3 types and options

**Files**:

- `lib/src/s3/s3_types.dart` (modified - cleanup after type extraction)
- `lib/src/s3/s3_options.dart` (modified - if needed)

**Message**:

```
refactor(s3): cleanup S3 types after core type extraction

Remove generic types that were moved to core/types.dart and
update imports. Keep only S3-specific types in s3_types.dart.
```

---

## Section 5: Public API Updates

**Goal**: Update public exports to include new extensions and types.

### Commit 5.1: Update public API exports

**Files**:

- `lib/fluppy.dart` (modified - export new types and extensions)

**Message**:

```
feat(core): export core types and S3 public extension

Export CancellationToken, UploadProgressInfo, UploadResponse,
and exception types from core/types.dart. Export S3FilePublic
extension for read-only S3 state access.

Users can now access generic types and S3-specific read-only
state via public extensions.
```

---

## Section 6: Test Updates

**Goal**: Update all tests to work with new API.

### Commit 6.1: Update core tests for read-only status

**Files**:

- `test/fluppy_file_test.dart` (modified - test read-only status)
- `test/fluppy_test.dart` (modified - if needed)

**Message**:

```
test(core): update tests for read-only status

Update tests to verify status is read-only and can only be
changed through Fluppy methods. Remove direct status mutations
from tests.
```

### Commit 6.2: Update S3 tests for extension-based state

**Files**:

- `test/s3_uploader_test.dart` (modified - use extensions)
- `test/s3_types_test.dart` (modified - if needed)
- `test/s3_options_test.dart` (modified - if needed)
- `test/integration/s3_integration_test.dart` (modified - use extensions)

**Message**:

```
test(s3): update tests to use extension-based state access

Update S3 tests to use S3FileState extension for internal state
access and S3FilePublic extension for read-only assertions.
Remove direct field access from tests.
```

---

## Section 7: Documentation

**Goal**: Add migration guide and update documentation.

### Commit 7.1: Add migration guide for v1 to v2

**Files**:

- `docs/migration/v1-to-v2.md` (NEW)

**Message**:

```
docs: add migration guide for v1.x to v2.0

Document breaking changes and migration steps for users upgrading
from v1.x to v2.0. Include examples of old vs new API usage.
```

### Commit 7.2: Update implementation plan status

**Files**:

- `docs/plans/20250113_api-encapsulation-improvements.md` (modified - mark complete)

**Message**:

```
docs: mark API encapsulation plan as completed

Update plan document to reflect completed implementation.
All phases are now complete and architecture matches Uppy's pattern.
```

---

## Section 8: Configuration and Examples

**Goal**: Update configuration files and example code.

### Commit 8.1: Update analysis options

**Files**:

- `analysis_options.yaml` (modified)
- `example/s3_real_app/analysis_options.yaml` (modified)

**Message**:

```
chore: update analysis_options.yaml

Update linter rules to match current codebase standards.
```

### Commit 8.2: Update example code

**Files**:

- `example/example.dart` (modified - use new API)
- `example/s3_real_app/lib/main.dart` (modified - use new API)

**Message**:

```
docs(example): update examples to use new API

Update example code to demonstrate new read-only status and
extension-based S3 state access. Remove deprecated field usage.
```

### Commit 8.3: Update pubspec.yaml

**Files**:

- `pubspec.yaml` (modified - if version or dependencies changed)

**Message**:

```
chore: update pubspec.yaml

Update version or dependencies if needed for v2.0 release.
```

---

## Summary

### Commit Count by Section:

1. **Core Types Extraction**: 1 commit
2. **S3 State Management Extensions**: 2 commits
3. **Core API Encapsulation**: 3 commits
4. **S3 Implementation Updates**: 2 commits
5. **Public API Updates**: 1 commit
6. **Test Updates**: 2 commits
7. **Documentation**: 2 commits
8. **Configuration and Examples**: 3 commits

**Total**: ~16 commits organized into 8 logical sections

### Key Principles:

- ✅ Each commit is focused and atomic
- ✅ Commits are ordered logically (dependencies first)
- ✅ Breaking changes are clearly marked
- ✅ Tests updated alongside implementation
- ✅ Documentation updated with changes

---

## Execution Order

Execute commits in this order to maintain build stability:

1. **Section 1**: Core Types Extraction (foundation)
2. **Section 2**: S3 Extensions (infrastructure)
3. **Section 3**: Core API Encapsulation (main feature)
4. **Section 4**: S3 Implementation Updates (uses new infrastructure)
5. **Section 5**: Public API Updates (exports new features)
6. **Section 6**: Test Updates (validates changes)
7. **Section 7**: Documentation (documents changes)
8. **Section 8**: Configuration and Examples (polish)

---

## Notes

- Each commit should be tested (`dart test`) before moving to next
- Run `dart format` and `dart analyze` after each commit
- Breaking changes should be clearly documented in commit messages
- Consider creating a release branch for v2.0 if not already done
