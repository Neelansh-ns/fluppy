# Uppy-Style Pause/Resume Architecture Refactor

**Created**: 2026-01-12
**Status**: Complete ✅

---

## Problem Statement

Current Fluppy pause/resume implementation has fundamental architectural issues:

1. **Treats pause/resume as separate lifecycles**:
   - `upload()` throws `PausedException` to exit when paused
   - `resume()` starts a NEW upload Future
   - In-flight HTTP requests from "paused" upload conflict with "resumed" upload

2. **Complex race condition handling**:
   - Three Sets tracking state: `_activeUploads`, `_pausedFiles`, `_resumingFiles`
   - Stale part detection to skip parts from paused upload
   - Force-removal from `_activeUploads` to allow resume
   - Timeout issues waiting for cleanup

3. **Doesn't match Uppy's proven architecture**:
   - Uppy's `MultipartUploader` instance **stays alive** during pause
   - Has `pause()` and `start()` methods that control flow
   - Upload Promise doesn't resolve until truly complete

## Uppy's Architecture (from research doc)

### Key Insight (Lines 756-799)

```typescript
class MultipartUploader {
  #abortController = new AbortController();
  static pausingUploadReason = Symbol('pausing upload, not an actual error');

  pause(): void {
    // Abort with special "pausing" reason
    this.#abortController.abort(pausingUploadReason);
    // Create new controller for when we resume
    this.#abortController = new AbortController();
  }

  start(): void {
    if (this.#uploadHasStarted) {
      // Resume: abort pending and restart with new controller
      if (!this.#abortController.signal.aborted) {
        this.#abortController.abort(pausingUploadReason);
      }
      this.#abortController = new AbortController();
      this.#resumeUpload();
    } else {
      // First start
      this.#createUpload();
    }
  }

  // Error handler ignores pause "errors"
  #onReject = (err: unknown) =>
    (err as any)?.cause === pausingUploadReason
      ? null  // Ignore pause errors
      : this.#onError(err);
}
```

**The controller stays alive. Pause doesn't exit - it just waits.**

---

## Proposed Solution

### 1. Create `MultipartUploadController` Class

New file: `lib/src/s3/multipart_upload_controller.dart`

```dart
class MultipartUploadController {
  final FluppyFile file;
  final S3UploaderOptions options;
  final ProgressCallback onProgress;
  final EventEmitter emitEvent;
  final http.Client httpClient;

  // State
  UploadState _state = UploadState.idle;
  CancellationToken? _currentToken;
  final Completer<UploadResponse> _completer = Completer();

  // For tracking
  bool _uploadStarted = false;

  /// Starts or resumes the upload
  Future<UploadResponse> start() async {
    if (_state == UploadState.cancelled) {
      throw CancelledException();
    }

    if (_uploadStarted) {
      // Resume: continue with new token
      await _resumeUpload();
    } else {
      // First start
      await _startUpload();
    }

    return _completer.future;
  }

  /// Pauses the upload (aborts current operations but stays alive)
  void pause() {
    if (_state == UploadState.completed || _state == UploadState.cancelled) {
      return;
    }

    _state = UploadState.paused;
    _currentToken?.cancel();  // Abort in-flight operations
    _currentToken = CancellationToken();  // New token for resume
  }

  /// Resumes the upload (continues with new token)
  void resume() {
    if (_state == UploadState.completed || _state == UploadState.cancelled) {
      return;
    }

    _state = UploadState.running;
    // start() will be called by external code
  }

  /// Cancels the upload permanently
  void cancel() {
    if (_state == UploadState.completed) {
      return;
    }

    _state = UploadState.cancelled;
    _currentToken?.cancel();

    if (!_completer.isCompleted) {
      _completer.completeError(CancelledException());
    }
  }

  Future<void> _startUpload() async {
    _state = UploadState.running;
    _currentToken = CancellationToken();
    _uploadStarted = true;

    try {
      // Create multipart upload
      final result = await options.createMultipartUpload(file);
      file.uploadId = result.uploadId;
      file.key = result.key;
      file.isMultipart = true;

      // Upload parts
      await _uploadParts();

      // Complete
      final response = await _completeUpload();

      _state = UploadState.completed;
      if (!_completer.isCompleted) {
        _completer.complete(response);
      }
    } catch (e) {
      if (e is CancelledException && _state == UploadState.paused) {
        // This is a pause, not an error - wait for resume
        return;
      }

      if (!_completer.isCompleted) {
        _completer.completeError(e);
      }
    }
  }

  Future<void> _resumeUpload() async {
    _state = UploadState.running;
    _currentToken = CancellationToken();

    try {
      // List parts from S3 (source of truth)
      final existingParts = await options.listParts(
        file,
        ListPartsOptions(
          uploadId: file.uploadId!,
          key: file.key!,
          signal: _currentToken,
        ),
      );

      // Replace in-memory state with S3 reality
      file.uploadedParts.clear();
      file.uploadedParts.addAll(existingParts);

      // Upload remaining parts
      await _uploadParts();

      // Complete
      final response = await _completeUpload();

      _state = UploadState.completed;
      if (!_completer.isCompleted) {
        _completer.complete(response);
      }
    } catch (e) {
      if (e is CancelledException && _state == UploadState.paused) {
        // This is a pause, not an error - wait for resume
        return;
      }

      if (!_completer.isCompleted) {
        _completer.completeError(e);
      }
    }
  }

  Future<void> _uploadParts() async {
    // Check if paused before starting
    if (_state == UploadState.paused) {
      throw CancelledException();
    }

    final chunkSize = options.getChunkSize(file);
    final totalParts = (file.size / chunkSize).ceil();

    // Find parts that need uploading
    final uploadedPartNumbers = file.uploadedParts.map((p) => p.partNumber).toSet();
    final partsToUpload = <int>[];
    for (int i = 1; i <= totalParts; i++) {
      if (!uploadedPartNumbers.contains(i)) {
        partsToUpload.add(i);
      }
    }

    if (partsToUpload.isEmpty) {
      return;  // All parts done
    }

    // Upload parts with concurrency limit
    final semaphore = Semaphore(options.maxConcurrentParts);
    final futures = <Future<void>>[];

    for (final partNumber in partsToUpload) {
      // Check pause before each part
      if (_state == UploadState.paused) {
        throw CancelledException();
      }

      final future = semaphore.run(() async {
        // Check pause again after acquiring semaphore
        if (_state == UploadState.paused) {
          throw CancelledException();
        }

        final part = await _uploadPart(partNumber, chunkSize, totalParts);

        // Only add part if still in running state
        if (_state == UploadState.running) {
          file.uploadedParts.add(part);
          // Report progress...
        }
      });

      futures.add(future);
    }

    await Future.wait(futures);
  }

  Future<S3Part> _uploadPart(int partNumber, int chunkSize, int totalParts) async {
    // Implementation similar to current _uploadPart
    // Uses _currentToken for cancellation
    // ...
  }

  Future<UploadResponse> _completeUpload() async {
    // Sort parts and complete
    file.uploadedParts.sort((a, b) => a.partNumber.compareTo(b.partNumber));

    final result = await options.completeMultipartUpload(
      file,
      CompleteMultipartOptions(
        uploadId: file.uploadId!,
        key: file.key!,
        parts: file.uploadedParts,
        signal: _currentToken,
      ),
    );

    return UploadResponse(
      location: result.location,
      eTag: result.eTag,
      key: file.key,
    );
  }
}

enum UploadState {
  idle,
  running,
  paused,
  cancelled,
  completed,
}
```

### 2. Update S3Uploader

```dart
class S3Uploader extends Uploader {
  // Remove: _pausedFiles, _activeUploads, _resumingFiles

  /// Active upload controllers
  final Map<String, MultipartUploadController> _controllers = {};

  @override
  Future<UploadResponse> upload(
    FluppyFile file, {
    required ProgressCallback onProgress,
    required EventEmitter emitEvent,
    CancellationToken? cancellationToken,
  }) async {
    if (options.useMultipart(file)) {
      // Create controller
      final controller = MultipartUploadController(
        file: file,
        options: options,
        onProgress: onProgress,
        emitEvent: emitEvent,
        httpClient: _httpClient,
      );

      _controllers[file.id] = controller;

      try {
        // Start upload - this Future won't complete until done or cancelled
        return await controller.start();
      } finally {
        _controllers.remove(file.id);
      }
    } else {
      return await _uploadSinglePart(file, onProgress, cancellationToken);
    }
  }

  @override
  Future<bool> pause(FluppyFile file) async {
    final controller = _controllers[file.id];
    if (controller == null) return false;

    controller.pause();
    return true;
  }

  @override
  Future<UploadResponse> resume(
    FluppyFile file, {
    required ProgressCallback onProgress,
    required EventEmitter emitEvent,
    CancellationToken? cancellationToken,
  }) async {
    final controller = _controllers[file.id];

    if (controller != null) {
      // Resume existing controller
      controller.resume();
      return await controller.start();  // Continue the same upload
    } else {
      // No controller exists - start new upload
      return await upload(
        file,
        onProgress: onProgress,
        emitEvent: emitEvent,
        cancellationToken: cancellationToken,
      );
    }
  }

  @override
  Future<void> cancel(FluppyFile file) async {
    final controller = _controllers[file.id];
    controller?.cancel();

    // Abort on server if multipart
    if (file.uploadId != null) {
      try {
        await options.abortMultipartUpload(
          file,
          AbortMultipartOptions(
            uploadId: file.uploadId!,
            key: file.key!,
          ),
        );
      } catch (e) {
        // Ignore errors during abort
      }
    }
  }
}
```

### 3. Update Fluppy Core

Minimal changes needed:
- Keep existing `pause()` and `resume()` methods
- Remove `PausedException` conversion logic (controller handles it internally)

---

## Benefits

1. **No Race Conditions**
   - Single controller per file
   - No concurrent upload processes
   - No need for `_activeUploads` / `_pausingFiles` / `_resumingFiles` Sets

2. **Simpler Code**
   - Controller encapsulates all state
   - No stale part detection needed
   - No force-removal from Sets
   - No timeout issues

3. **Uppy Alignment**
   - Matches Uppy's `MultipartUploader` architecture
   - Upload stays alive during pause
   - Clear state machine: idle → running → paused → running → completed

4. **Better Control**
   - Pause is instantaneous (just sets flag)
   - Resume continues same upload (no new process)
   - Controller manages its own lifecycle

---

## Implementation Steps

### Phase 1: Create Controller ✅
- [x] Create `MultipartUploadController` class
- [x] Implement state machine (idle, running, paused, cancelled, completed)
- [x] Implement `start()`, `pause()`, `resume()`, `cancel()` methods
- [x] Use `Completer` to control main Future

### Phase 2: Update S3Uploader ✅
- [x] Remove `_pausedFiles`, `_activeUploads`, `_resumingFiles` Sets
- [x] Add `_controllers` Map
- [x] Update `upload()` to create and use controller
- [x] Update `pause()` to call controller.pause()
- [x] Update `resume()` to continue existing controller or create new one for existing uploads
- [x] Update `cancel()` to call controller.cancel()

### Phase 3: Clean Up ✅
- [x] Remove stale part detection logic
- [x] Remove force-removal logic
- [x] Remove PausedException conversion in upload()
- [x] Simplify error handling
- [x] Remove duplicate _Semaphore class

### Phase 4: Testing ✅
- [x] Update existing tests (pause no longer throws PausedException)
- [x] Fix "resume continues from where it left off" test
- [x] Fix "resume trusts S3 list completely" test
- [x] Fix integration test "pauses multipart upload and resumes"
- [x] All 119 tests passing

---

## Testing Strategy

All existing tests should pass:
- `pause stops upload and throws PausedException` → Controller stays alive, no exception
- `resume trusts S3 list completely` → Same behavior
- `prevents duplicate uploads from rapid pause/resume` → Simpler now (same controller)
- `resume with all parts done skips upload` → Same behavior

---

## Migration Notes

This is a **significant refactor** but:
- Public API unchanged (pause/resume methods same)
- Tests may need updates (controller doesn't throw PausedException)
- Behavior will be more reliable
- Code will be much simpler

---

## Post-Implementation Fixes

### Issue 1: Parts Not in Ascending Order ✅

**Problem**:
- S3 error: "The list of parts was not in ascending order"
- Root cause: Parts completing concurrently were being added to `file.uploadedParts` AFTER sorting
- The `_completeUpload()` method sorted the live list, but in-flight parts continued to complete and append unsorted

**Solution**:
- Create an immutable sorted copy of the parts list instead of sorting in-place
- Use the snapshot for completion, preventing late-completing parts from corrupting the order

**Code Change** ([multipart_upload_controller.dart:508-518](lib/src/s3/multipart_upload_controller.dart#L508-L518)):
```dart
// Before (broken):
file.uploadedParts.sort((a, b) => a.partNumber.compareTo(b.partNumber));
final result = await options.completeMultipartUpload(
  file,
  CompleteMultipartOptions(parts: file.uploadedParts, ...)
);

// After (fixed):
final sortedParts = List<S3Part>.from(file.uploadedParts)
  ..sort((a, b) => a.partNumber.compareTo(b.partNumber));
final result = await options.completeMultipartUpload(
  file,
  CompleteMultipartOptions(parts: sortedParts, ...) // Immutable snapshot
);
```

### Issue 2: In-flight HTTP Requests Not Aborted ✅

**Problem**:
- After pause/cancel, in-flight HTTP requests continue and log "upload completed"
- Confusing logs showing parts completing after upload was paused

**Root Cause**:
- Dart's `http` package doesn't support aborting in-flight HTTP requests
- `CancellationToken.cancel()` only prevents NEW operations from starting
- Already-started HTTP PUT requests continue until completion

**Solution**:
- ✅ State check already prevents late-completing parts from being added to list ([multipart_upload_controller.dart:314](lib/src/s3/multipart_upload_controller.dart#L314))
- ✅ Improved logging to clarify when parts complete but are discarded ([multipart_upload_controller.dart:388-393](lib/src/s3/multipart_upload_controller.dart#L388-L393))
- ✅ Added documentation explaining the limitation ([multipart_upload_controller.dart:450-454](lib/src/s3/multipart_upload_controller.dart#L450-L454))

**Code Changes**:
```dart
// Log distinguishes between kept and discarded parts:
if (_state == UploadState.running) {
  print('part $partNumber: upload completed (eTag: ${uploadResult.eTag})');
} else {
  print('part $partNumber: upload completed but state is $_state (will be discarded)');
}

// State check ensures discarded parts aren't added:
if (_state == UploadState.running) {
  file.uploadedParts.add(part);
} else {
  print('Part $partNumber completed but state is $_state, skipping');
}
```

**Future Enhancement**:
Consider switching to `dio` package which supports request cancellation for more responsive abort behavior.

---

## References

- `docs/research/20260112_uppy-pause-resume-cancel.md` - Lines 756-799 (MultipartUploader)
- Uppy source: `packages/@uppy/aws-s3/src/MultipartUploader.ts`
