# Implement Plan - Fluppy

You are tasked with implementing an approved technical plan from `docs/plans/`. These plans contain phases with specific changes and success criteria for the **Fluppy Flutter package**.

---

## Context: What is Fluppy?

Fluppy is a **Flutter/Dart package for file uploads**, inspired by [Uppy.js](https://uppy.io/). The goal is to achieve **1:1 feature parity** with Uppy while following Dart/Flutter best practices.

**Key Reference**: Always consult [`docs/uppy-study.md`](uppy-study.md) for Uppy's architecture and patterns.

---

## Getting Started

When given a plan path:

1. **Read the plan completely**
   - Check for any existing checkmarks (`- [x]`)
   - Understand all phases and their dependencies
   - Note the Uppy reference sections

2. **Read referenced documentation**
   - Read `docs/uppy-study.md` for the relevant feature
   - Read any original spec or ticket files mentioned
   - Understand how Uppy implements this feature

3. **Read implementation files**
   - Read all files mentioned in the plan **FULLY** (never use limit/offset)
   - Understand existing patterns in the codebase
   - Look at similar implementations (e.g., S3Uploader as reference)

4. **Verify Uppy alignment**
   - Check that the planned API matches Uppy conventions
   - Verify event names follow Uppy patterns
   - Ensure lifecycle hooks align with Uppy

5. **Create a todo list**
   - Track your progress through phases
   - Note verification steps

6. **Start implementing**
   - Begin with Phase 1 once you understand the plan

If no plan path provided, ask for one.

---

## Phase Approval Requirement

**IMPORTANT**: By default, you **MUST** wait for explicit user approval before proceeding to the next phase.

### After Completing Each Phase:

1. **Run verification checks**:
   - Code formatting: `dart format .`
   - Static analysis: `dart analyze`
   - Tests: `dart test`
   - Example runs: `dart run example/example.dart` (if applicable)

2. **Fix any issues** before proceeding

3. **Update checkboxes** in the plan file using Edit tool

4. **Present a summary** of what was completed:
   ```
   Phase 1 complete. Summary:
   - Created [files]
   - Implemented [functionality]
   - All verification checks pass
   - Uppy alignment verified: [specific points]

   Ready to proceed to Phase 2: [Phase Name]?
   ```

5. **Wait for user approval** to continue

### Exception: Autonomous Implementation

If the user explicitly instructs you to proceed without waiting (e.g., "implement all phases", "don't wait for approval", "run through all phases"), you may proceed autonomously through all phases.

---

## Implementation Philosophy

Plans are carefully designed to align with Uppy, but implementation requires judgment. Your job is to:

- **Follow the plan's intent** while adapting to what you find
- **Maintain Uppy alignment** - verify API, events, and patterns match
- **Implement each phase fully** before moving to the next
- **Use Dart best practices** (Streams, sealed classes, async/await)
- **Keep the public API minimal** - only export what's necessary
- **Update checkboxes** in the plan as you complete sections

### When Things Don't Match the Plan

If you encounter a mismatch or issue:

1. **STOP** and think deeply about why the plan can't be followed
2. **Check Uppy alignment** - does the mismatch affect Uppy parity?
3. **Present the issue clearly**:

   ```
   Issue in Phase [N]:
   Expected: [what the plan says]
   Found: [actual situation]
   Uppy Impact: [how this affects Uppy alignment]
   Why this matters: [explanation]

   Proposed Solution: [your recommendation]

   How should I proceed?
   ```

---

## Verification Approach

### Package-Specific Verification Commands

```bash
# Get dependencies (if pubspec.yaml changed)
dart pub get

# Code formatting
dart format .

# Static analysis (ensure no warnings)
dart analyze

# Run all tests
dart test

# Run specific test file
dart test test/my_feature_test.dart

# Run example (if applicable)
dart run example/example.dart

# Check package health
dart pub publish --dry-run
```

### Verification Process

1. **Run verification commands** at the end of each phase
2. **Fix any issues** before marking phase complete
3. **Update progress** in:
   - The plan markdown file (check off items using Edit)
   - Your todos (using TodoWrite)
4. **Verify Uppy alignment**:
   - API naming matches Uppy
   - Events match Uppy's event system
   - Behavior aligns with Uppy documentation

### Success Criteria Checklist

Before marking a phase complete, verify:

- [ ] Code compiles: `dart analyze` shows no errors
- [ ] Tests pass: `dart test` succeeds
- [ ] Code is formatted: `dart format .` makes no changes
- [ ] Example demonstrates feature (if applicable)
- [ ] **Uppy alignment verified**: API/events match Uppy conventions
- [ ] Public API is minimal (only necessary exports)
- [ ] Documentation updated (dartdoc, README, CHANGELOG)
- [ ] Checkboxes updated in plan file

---

## Uppy Alignment Verification

After implementing each phase, verify alignment with Uppy:

### API Naming
```dart
// ✅ Good - Matches Uppy
fluppy.addFile(file);
fluppy.upload();
fluppy.pauseAll();

// ❌ Bad - Doesn't match Uppy
fluppy.insertFile(file);
fluppy.startUpload();
fluppy.pauseEverything();
```

### Event Names
```dart
// ✅ Good - Matches Uppy events
class FileAdded extends FluppyEvent {}
class UploadProgress extends FluppyEvent {}
class UploadComplete extends FluppyEvent {}

// ❌ Bad - Custom naming
class FileInserted extends FluppyEvent {}
class ProgressUpdated extends FluppyEvent {}
class UploadFinished extends FluppyEvent {}
```

### Behavior
- Check `docs/uppy-study.md` for Uppy's behavior
- Test that your implementation behaves the same way
- Document any intentional deviations (with reasoning)

---

## Common Implementation Patterns

### Adding a New Uploader

1. **Create directory**: `lib/src/[uploader_name]/`
2. **Create files**:
   - `[uploader]_uploader.dart` - Main uploader class
   - `[uploader]_options.dart` - Configuration options
   - `[uploader]_types.dart` - Data types/models
3. **Extend Uploader**:
   ```dart
   class TusUploader extends Uploader {
     final TusOptions options;

     TusUploader({required this.options});

     @override
     Future<UploadResponse> upload(
       FluppyFile file,
       CancellationToken cancellationToken,
     ) async {
       // Implementation
     }
   }
   ```
4. **Implement lifecycle**:
   - Handle upload execution
   - Emit progress events
   - Support pause/resume/cancel
   - Handle errors appropriately
5. **Write tests**: `test/[uploader]_test.dart`
6. **Update example**: Show usage in `example/example.dart`
7. **Update README**: Document the new uploader
8. **Update CHANGELOG**: Note the addition

### Adding Core Functionality (e.g., Preprocessing)

1. **Read Uppy implementation** from `docs/uppy-study.md`
2. **Modify core class**: `lib/src/core/fluppy.dart`
3. **Add event types**: `lib/src/core/events.dart` (if needed)
4. **Implement lifecycle methods**:
   ```dart
   // Add processor registration
   void addPreProcessor(PreProcessor processor) {
     _preProcessors.add(processor);
   }

   // Execute in upload pipeline
   Future<void> _runPreProcessors(List<FluppyFile> files) async {
     for (final processor in _preProcessors) {
       await processor(files);
     }
   }
   ```
5. **Update tests**: Test the new functionality
6. **Update documentation**: README, dartdocs, example

### Adding Configuration Option

1. **Check Uppy's option** in `docs/uppy-study.md`
2. **Add to appropriate options class**:
   ```dart
   class FluppyOptions {
     final int? maxFileSize;
     final List<String>? allowedFileTypes;

     const FluppyOptions({
       this.maxFileSize,
       this.allowedFileTypes,
     });
   }
   ```
3. **Implement validation/behavior**
4. **Add tests** for new option
5. **Document** in dartdoc and README

### Modifying Public API

⚠️ **IMPORTANT**: Public API changes may be breaking changes!

1. **Check semver impact**:
   - Breaking change → Major version bump
   - New feature → Minor version bump
   - Bug fix → Patch version bump

2. **Consider backwards compatibility**:
   - Can we add without breaking existing code?
   - Use optional parameters or default values
   - Deprecate old APIs rather than removing immediately

3. **Update all affected code**:
   - Core classes
   - Uploader implementations
   - Tests
   - Examples
   - Documentation

4. **Update CHANGELOG**:
   - Clearly mark breaking changes
   - Provide migration guide if needed

---

## Testing Strategy

### Unit Tests

Test individual classes and methods:

```dart
test('addFile adds file to collection', () {
  final fluppy = Fluppy(uploader: MockUploader());
  final file = FluppyFile.fromPath('test.txt', path: '/path/to/test.txt');

  fluppy.addFile(file);

  expect(fluppy.files, contains(file));
});
```

### Integration Tests

Test complete workflows:

```dart
test('upload workflow completes successfully', () async {
  final fluppy = Fluppy(uploader: MockUploader());
  final file = FluppyFile.fromPath('test.txt', path: '/path/to/test.txt');

  fluppy.addFile(file);

  final events = <FluppyEvent>[];
  fluppy.events.listen(events.add);

  await fluppy.upload();

  expect(events, contains(isA<UploadComplete>()));
  expect(file.status, FileStatus.complete);
});
```

### Mock Uploaders

Use mocks for testing without network:

```dart
class MockUploader extends Uploader {
  @override
  Future<UploadResponse> upload(
    FluppyFile file,
    CancellationToken cancellationToken,
  ) async {
    // Simulate upload with delay
    await Future.delayed(Duration(milliseconds: 100));

    return UploadResponse(
      uploadURL: 'https://mock.example.com/file.txt',
    );
  }
}
```

### Test Coverage Goals

- Aim for **>80% code coverage**
- Test all public APIs
- Test error cases and edge cases
- Test pause/resume/cancel scenarios

---

## Documentation Requirements

### dartdoc Comments

All public APIs must have dartdoc comments:

```dart
/// Adds a file to the upload queue.
///
/// The [file] will be added to the internal collection and will be
/// included in the next [upload] call. Files can be added before or
/// during uploads.
///
/// Example:
/// ```dart
/// final file = FluppyFile.fromPath(
///   'photo.jpg',
///   path: '/path/to/photo.jpg',
/// );
/// fluppy.addFile(file);
/// ```
///
/// See also:
/// - [addFiles] for adding multiple files at once
/// - [removeFile] for removing files from the queue
void addFile(FluppyFile file) {
  // Implementation
}
```

### README Updates

Keep README current with:
- Feature list (what's implemented)
- Installation instructions
- Quick start example
- API overview
- Links to examples
- **Uppy comparison** (what's implemented vs Uppy)

### CHANGELOG

Follow [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
## [Unreleased]

### Added
- Tus uploader support for resumable uploads
- File restrictions (size, type, count validation)

### Changed
- Improved error messages for failed uploads

### Fixed
- Multipart upload resume with large files

## [0.1.0] - 2026-01-11

### Added
- Initial release with S3 uploader
- Core file management and event system
- Pause/resume/retry functionality
```

### Example Updates

Update `example/example.dart` to demonstrate new features:

```dart
void main() async {
  // Example demonstrating new feature
  final fluppy = Fluppy(
    uploader: TusUploader(
      endpoint: 'https://tusd.tusdemo.net/files/',
    ),
  );

  // ... rest of example
}
```

---

## If You Get Stuck

When something isn't working as expected:

1. **Read the existing code** thoroughly
2. **Check `doc/uppy-study.md`** - How does Uppy handle this?
3. **Check `doc/`** - How does other research and plans implemented look like?
4. **Look at similar implementations** - How did S3Uploader do it?
5. **Check the tests** - What's the expected behavior?
6. **Present the issue clearly** with context

### When to Ask for Help

- You can't determine how to align with Uppy
- The plan conflicts with the current codebase
- You need clarification on design decisions
- You discover a missing dependency or constraint

---

## Resuming Work

If the plan has existing checkmarks:

1. **Trust completed work** - Don't re-verify unless something seems wrong
2. **Pick up from first unchecked item**
3. **Read the context** around that phase
4. **Continue implementation**

---

## Package Structure Reference

```
fluppy/
├── lib/
│   ├── fluppy.dart              # Public API exports
│   └── src/
│       ├── core/                # Core framework
│       │   ├── fluppy.dart      # Main orchestrator
│       │   ├── uploader.dart    # Abstract uploader
│       │   ├── fluppy_file.dart # File model
│       │   └── events.dart      # Event system
│       └── [uploader]/          # Uploader implementations
│           ├── [name]_uploader.dart
│           ├── [name]_options.dart
│           └── [name]_types.dart
├── test/                        # Tests mirror lib/ structure
├── example/                     # Usage examples
├── docs/
│   ├── uppy-study.md           # Uppy reference
│   ├── plans/                  # Implementation plans
│   └── research/               # Research documents
├── pubspec.yaml                # Package metadata
├── README.md                   # Documentation
├── CHANGELOG.md                # Version history
└── LICENSE                     # MIT License
```

---

## Common Gotchas

### 1. Public API Exposure

Only export what's necessary from `lib/fluppy.dart`:

```dart
// lib/fluppy.dart

// Export core classes
export 'src/core/fluppy.dart';
export 'src/core/fluppy_file.dart';
export 'src/core/uploader.dart';
export 'src/core/events.dart';

// Export uploaders
export 'src/s3/s3_uploader.dart';
export 'src/s3/s3_options.dart';
export 'src/s3/s3_types.dart';

// Don't export internal implementation details
// (anything in src/ not explicitly exported is private)
```

### 2. Breaking Changes

Be very careful with breaking changes:

- **Breaking**: Removing public API, changing method signatures
- **Non-breaking**: Adding optional parameters, new methods, new classes

If you must break, increment major version and document migration.

### 3. Uppy Naming Conventions

Always check Uppy first:

| Wrong | Right | Uppy Equivalent |
|-------|-------|-----------------|
| `insertFile()` | `addFile()` | `uppy.addFile()` |
| `deleteFile()` | `removeFile()` | `uppy.removeFile()` |
| `startUpload()` | `upload()` | `uppy.upload()` |

### 4. Event System

Use sealed classes for type-safe events:

```dart
// ✅ Good
sealed class FluppyEvent {}

class UploadProgress extends FluppyEvent {
  final String fileId;
  final int bytesUploaded;
  final int bytesTotal;

  UploadProgress({
    required this.fileId,
    required this.bytesUploaded,
    required this.bytesTotal,
  });
}

// Usage with pattern matching
fluppy.events.listen((event) {
  switch (event) {
    case UploadProgress(:final bytesUploaded, :final bytesTotal):
      print('Progress: $bytesUploaded / $bytesTotal');
  }
});
```

### 5. Async File Operations

Remember that file I/O is async:

```dart
// ✅ Good
final bytes = await file.readAsBytes();

// ❌ Bad - sync operations block
final bytes = file.readAsBytesSync(); // Avoid if possible
```

---

## Final Checklist Before Completion

Before marking the entire implementation complete:

- [ ] All phases completed and verified
- [ ] All tests pass: `dart test`
- [ ] No analysis warnings: `dart analyze`
- [ ] Code is formatted: `dart format .`
- [ ] Example runs successfully: `dart run example/example.dart`
- [ ] README is updated with new features
- [ ] CHANGELOG is updated with changes
- [ ] Public API is documented with dartdoc
- [ ] **Uppy alignment verified** for all new features
- [ ] Plan file checkboxes all marked complete
- [ ] Package can be published: `dart pub publish --dry-run`

---

## Summary

**Remember:**
1. ✅ Read the plan and all referenced files completely
2. ✅ Verify Uppy alignment at every step
3. ✅ Follow Dart best practices (Streams, sealed classes, async/await)
4. ✅ Keep public API minimal and well-documented
5. ✅ Write comprehensive tests
6. ✅ Update documentation (dartdoc, README, CHANGELOG)
7. ✅ Wait for approval between phases (unless told otherwise)
8. ✅ Use Edit tool to update plan checkboxes

**Goal**: Implement features that match Uppy's behavior while following Dart/Flutter best practices!

---

## User Input

$ARGUMENTS
