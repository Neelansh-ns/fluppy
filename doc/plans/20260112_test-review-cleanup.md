# Test Suite Review and Cleanup Plan

**Created**: 2026-01-12  
**Status**: Draft  
**Goal**: Review all test cases, keep crucial ones, remove useless ones, add missing critical tests

---

## Current Test Suite Overview

### Test Files

1. **`test/s3_uploader_test.dart`** (~1449 lines) - Main S3 uploader tests
2. **`test/fluppy_test.dart`** (~437 lines) - Core Fluppy orchestration tests
3. **`test/fluppy_file_test.dart`** (~243 lines) - File model tests
4. **`test/s3_types_test.dart`** (~247 lines) - Type/utility tests
5. **`test/s3_options_test.dart`** (~331 lines) - Configuration tests
6. **`test/integration/s3_integration_test.dart`** (~661 lines) - Integration tests

**Total**: ~32 test groups, ~100+ individual test cases

---

## Test Categorization

### 🔴 CRITICAL Tests (Must Keep)

These tests catch critical bugs and ensure core functionality works:

#### S3Uploader - Core Functionality

- ✅ `uploads small file using getUploadParameters` - Basic single-part upload
- ✅ `uploads large file using multipart` - Basic multipart upload
- ✅ `calculates correct number of parts` - Part calculation logic
- ✅ `respects maxConcurrentParts limit` - Concurrency control
- ✅ `pause stops upload and waits for resume` - **CRITICAL**: Pause/resume flow
- ✅ `resume continues from where it left off` - **CRITICAL**: Resume correctness
- ✅ `resume trusts S3 list completely` - **CRITICAL**: S3 as source of truth
- ✅ `resume with all parts done skips upload` - **CRITICAL**: Early exit optimization
- ✅ `cancel aborts multipart upload` - Cleanup on cancel

#### Error Handling

- ✅ `retries failed HTTP upload with exponential backoff` - Retry logic
- ✅ `gives up after max retries` - Retry limits
- ✅ `user callback failures are NOT retried` - **CRITICAL**: No retry for user errors
- ✅ `handles expired presigned URL detection` - **CRITICAL**: Expired URL handling

#### Controller Lifecycle (Uppy Pattern)

- ✅ `pause stops upload and waits (in-flight parts)` - **CRITICAL**: Controller persistence
- ✅ `prevents duplicate uploads from rapid pause/resume` - **CRITICAL**: Race condition protection

#### Integration Tests

- ✅ `complete single-part upload flow with real HTTP` - End-to-end single-part
- ✅ `complete multipart upload flow with real HTTP` - End-to-end multipart
- ✅ `pauses multipart upload and resumes from where it left off` - **CRITICAL**: Real pause/resume

---

### 🟡 IMPORTANT Tests (Should Keep)

These tests verify important behavior but are less critical:

#### Configuration & Defaults

- ✅ `uses default multipart threshold (100 MB)` - Default behavior
- ✅ `uses default chunk size (5 MB)` - Default behavior
- ✅ `uses default limit (6 concurrent files)` - Default behavior
- ✅ `uses default maxConcurrentParts (3)` - Default behavior

#### Progress & Events

- ✅ `emits PartUploaded events for each part` - Event emission
- ✅ `tracks progress accurately for single-part upload` - Progress tracking
- ✅ `emits UploadProgress events` - Event system

#### Edge Cases

- ✅ `includes custom headers in single-part upload` - Header handling
- ✅ `uses PUT method by default for single-part` - Method selection
- ✅ `handles missing ETag gracefully` - Error handling (currently skipped)

#### Retry Logic

- ✅ `uses Uppy-style retry delays array` - Uppy compatibility
- ✅ `multipart upload fails if part upload fails` - Error propagation

---

### 🟢 NICE-TO-HAVE Tests (Consider Removing)

These tests verify minor details that are unlikely to catch bugs:

#### Type Tests (Mostly Trivial)

- ❓ `creates with required fields` (multiple) - Just constructor tests
- ❓ `creates with optional fields` - Just constructor tests
- ❓ `fromJson parses correctly` - JSON parsing (if types are simple)
- ❓ `toJson serializes correctly` - JSON serialization (if types are simple)

**Recommendation**: Keep 1-2 representative tests, remove duplicates

#### File Model Tests

- ❓ `generates unique id` - UUID generation (library responsibility)
- ❓ `allows custom id` - Simple property test
- ❓ `getBytes returns original bytes` - Trivial for bytes source
- ❓ `getChunk returns correct slice` - Basic array slicing

**Recommendation**: Keep only if they catch real bugs

#### Fluppy Core Tests

- ❓ `addFile adds file to queue` - Trivial getter test
- ❓ `getFile returns file by id` - Trivial getter test
- ❓ `pendingFiles returns only pending files` - Trivial filter test

**Recommendation**: Keep only if they verify complex logic

---

### 🔴 REDUNDANT Tests (Should Remove)

These tests duplicate functionality or test implementation details:

1. **Duplicate pause/resume tests**:

   - `pause stops upload and waits for resume` (line 393)
   - `pause stops upload and waits (in-flight parts)` (line 557)
   - **Action**: Keep one comprehensive test, remove duplicate

2. **Trivial configuration tests**:

   - Multiple tests for default values that are just constants
   - **Action**: Consolidate into one "defaults" test

3. **Simple getter tests**:
   - Tests that just verify a getter returns a value
   - **Action**: Remove unless they verify complex logic

---

## Missing Critical Tests

### 🔴 HIGH PRIORITY - Must Add

#### 1. Controller Lifecycle Tests

```dart
test('controller persists during pause and is removed on completion', () async {
  // Verify controller stays in _controllers map during pause
  // Verify controller is removed after completion
  // Verify controller is removed on error
  // Verify controller is NOT removed on pause
});
```

#### 2. Resume Edge Cases

```dart
test('resume creates new controller if lost (app restart scenario)', () async {
  // File has uploadId but no controller exists
  // Should create new controller with continueExisting: true
  // Should list parts from S3
  // Should complete successfully
});

test('resume throws PausedException if paused again during resume', () async {
  // Start resume
  // Pause during resume
  // Should throw PausedException
  // Controller should stay alive
});
```

#### 3. AllUploadsComplete Event

```dart
test('AllUploadsComplete not emitted when files are paused', () async {
  // Upload multiple files
  // Pause one file
  // Complete others
  // AllUploadsComplete should NOT fire
});

test('AllUploadsComplete fires after resume completes', () async {
  // Upload multiple files
  // Pause one file
  // Complete others
  // Resume paused file
  // AllUploadsComplete should fire when all complete
});
```

#### 4. Progress Edge Cases

```dart
test('progress reaches 100% before completion', () async {
  // All parts uploaded but _completeUpload not called yet
  // Progress should show 100%
  // Resume should skip UploadResumed event
  // Should complete silently
});
```

#### 5. Single-Part Pause

```dart
test('pause returns false for single-part uploads', () async {
  // Single-part upload (useMultipart returns false)
  // Call pause()
  // Should return false
  // Should not affect upload
});
```

#### 6. Cancel Cleanup

```dart
test('cancel removes controller from map', () async {
  // Start multipart upload
  // Cancel upload
  // Controller should be removed from _controllers map
  // abortMultipartUpload should be called
});
```

#### 7. Error vs Pause Distinction

```dart
test('distinguishes pause from real cancellation', () async {
  // Pause should use _pausingReason
  // Cancel should use different reason
  // _isPausingError should correctly identify pause
});
```

### 🟡 MEDIUM PRIORITY - Should Add

#### 8. Race Conditions

```dart
test('rapid pause/resume does not create duplicate controllers', () async {
  // Rapidly call pause/resume multiple times
  // Should only have one controller
  // Should not create duplicate uploads
});
```

#### 9. State Transitions

```dart
test('controller state machine transitions correctly', () async {
  // idle -> running -> paused -> running -> completed
  // Verify invalid transitions are prevented
});
```

#### 10. Memory Leaks

```dart
test('controllers are cleaned up on dispose', () async {
  // Create multiple uploads
  // Dispose uploader
  // _controllers map should be empty
});
```

---

## Test Cleanup Actions

### Phase 1: Remove Redundant Tests

1. **Remove duplicate pause/resume tests**:

   - Keep: `pause stops upload and waits for resume` (comprehensive)
   - Remove: `pause stops upload and waits (in-flight parts)` (duplicate)

2. **Consolidate configuration tests**:

   - Merge all "default" tests into one comprehensive test
   - Remove individual default tests

3. **Remove trivial getter tests**:
   - Remove tests that just verify getters return values
   - Keep only if they verify complex logic

### Phase 2: Add Missing Critical Tests

1. Add controller lifecycle tests (HIGH PRIORITY)
2. Add resume edge case tests (HIGH PRIORITY)
3. Add AllUploadsComplete event tests (HIGH PRIORITY)
4. Add progress edge case tests (HIGH PRIORITY)
5. Add single-part pause test (HIGH PRIORITY)

### Phase 3: Improve Test Organization

1. **Group related tests**:

   - Controller lifecycle group
   - Resume edge cases group
   - Event emission group
   - Error handling group

2. **Add test documentation**:
   - Document what each test verifies
   - Explain why it's critical
   - Reference Uppy pattern if applicable

---

## Test Quality Improvements

### 1. Better Test Names

- Use descriptive names that explain what's being tested
- Include expected behavior in name
- Example: `controller_persists_during_pause_and_removed_on_completion`

### 2. Better Assertions

- Verify state changes, not just final state
- Check intermediate states where relevant
- Verify cleanup happens

### 3. Better Test Isolation

- Each test should be independent
- Clean up resources in tearDown
- Don't rely on test execution order

### 4. Better Mocking

- Use consistent mock patterns
- Create reusable mock helpers
- Document mock behavior

---

## Recommended Test Structure

```
test/
├── s3_uploader_test.dart
│   ├── group('Single-part upload')
│   │   ├── test('uploads small file')
│   │   └── test('pause returns false for single-part')
│   ├── group('Multipart upload')
│   │   ├── test('uploads large file')
│   │   ├── test('calculates correct number of parts')
│   │   └── test('respects maxConcurrentParts limit')
│   ├── group('Pause/Resume') [CRITICAL]
│   │   ├── test('pause stops upload and waits for resume')
│   │   ├── test('resume continues from where it left off')
│   │   ├── test('resume creates new controller if lost')
│   │   ├── test('resume throws PausedException if paused again')
│   │   ├── test('prevents duplicate uploads from rapid pause/resume')
│   │   └── test('resume with all parts done skips upload')
│   ├── group('Controller Lifecycle') [NEW - CRITICAL]
│   │   ├── test('controller persists during pause')
│   │   ├── test('controller removed on completion')
│   │   ├── test('controller removed on error')
│   │   ├── test('controller removed on cancel')
│   │   └── test('controller NOT removed on pause')
│   ├── group('Error Handling')
│   │   ├── test('retries failed HTTP upload')
│   │   ├── test('gives up after max retries')
│   │   ├── test('user callback failures NOT retried')
│   │   └── test('handles expired presigned URL')
│   └── group('Retry Logic')
│       ├── test('exponential backoff')
│       └── test('Uppy-style retry delays')
├── fluppy_test.dart
│   ├── group('Events') [IMPROVE]
│   │   ├── test('AllUploadsComplete not emitted when paused') [NEW]
│   │   └── test('AllUploadsComplete fires after resume') [NEW]
│   └── group('Progress') [IMPROVE]
│       └── test('progress reaches 100% before completion') [NEW]
├── fluppy_file_test.dart [SIMPLIFY]
│   └── Keep only non-trivial tests
├── s3_types_test.dart [SIMPLIFY]
│   └── Keep 1-2 representative tests per type
├── s3_options_test.dart [CONSOLIDATE]
│   └── Merge default tests into one
└── integration/
    └── s3_integration_test.dart [KEEP ALL]
        └── All integration tests are valuable
```

---

## Success Criteria

After cleanup:

- ✅ **~60-70 focused test cases** (down from 100+)
- ✅ **All critical edge cases covered**
- ✅ **No redundant tests**
- ✅ **All tests have clear purpose**
- ✅ **Tests catch real bugs**
- ✅ **Test execution time < 30 seconds**

---

## Implementation Order

1. **Phase 1**: Add missing critical tests (HIGH PRIORITY)
2. **Phase 2**: Remove redundant tests
3. **Phase 3**: Consolidate similar tests
4. **Phase 4**: Improve test organization and documentation

---

## Notes

- Keep integration tests as-is (they're all valuable)
- Focus cleanup on unit tests
- Don't remove tests that catch edge cases
- When in doubt, keep the test (better safe than sorry)
