# Contributors Guide - Fluppy

**This file is for Claude Code and other LLM/AI coding agents.**

---

## MANDATORY: Read Before ANY Changes

**CRITICAL REQUIREMENT FOR ALL AI AGENTS**: Before making **ANY** code changes, planning, or implementation in this codebase, you **MUST** read the complete documentation to understand Fluppy's architecture and alignment goals.

### Required Actions

**READ THESE FILES IMMEDIATELY**:

1. **[`docs/uppy-study.md`](docs/research/uppy-study.md)** - Uppy architecture reference (MOST IMPORTANT)
2. **[`docs/plan.md`](docs/plan.md)** - How to create implementation plans
3. **[`docs/implement.md`](docs/implement.md)** - How to implement approved plans
4. **[`docs/research.md`](docs/research.md)** - How to research the codebase
5. **[`README.md`](README.md)** - Package overview and usage

This is **NOT optional**. This is a **MANDATORY** requirement.

---

## Project Overview

**Fluppy** is a Flutter/Dart package for file uploads, inspired by **Uppy.js**.

- **Platform**: Dart package (works with Flutter, CLI, server-side Dart)
- **Goal**: Achieve **1:1 feature parity** with Uppy.js
- **Architecture**: Plugin-based modular architecture with abstract uploaders
- **Key Technologies**: Dart, Streams, Sealed Classes, Abstract Classes

### Core Philosophy

1. **Uppy Alignment**: Fluppy aims to replicate Uppy's API, architecture, and patterns
2. **Dart-Idiomatic**: Use Dart/Flutter best practices (Streams, sealed classes, etc.)
3. **Modular**: Plugin-based architecture with swappable uploaders
4. **Headless**: No UI included (bring your own Flutter widgets)
5. **Backend-Agnostic**: Works with any upload backend through uploader implementations

---

## Quick Reference

### Development Commands

```bash
# Get dependencies
dart pub get

# Run tests
dart test

# Run specific test file
dart test test/fluppy_test.dart

# Code formatting
dart format .

# Static analysis
dart analyze

# Run example
dart run example/example.dart
```

### Key Directories

```
lib/
├── fluppy.dart                  # Public API exports
└── src/
    ├── core/                    # Core framework
    │   ├── fluppy.dart          # Main orchestrator
    │   ├── uploader.dart        # Abstract uploader base
    │   ├── fluppy_file.dart     # File model
    │   └── events.dart          # Event system (sealed classes)
    └── [uploader]/              # Uploader implementations
        ├── s3/                  # AWS S3 uploader
        ├── tus/                 # Tus resumable uploads (planned)
        └── http/                # HTTP/XHR uploader (planned)

test/                            # Unit and integration tests
example/                         # Usage examples
docs/                            # Documentation and guides
```

---

## Core Principles for AI Agents

### 1. Uppy Alignment is CRITICAL

**Before implementing ANY feature:**
1. Read `docs/uppy-study.md` to understand Uppy's approach
2. Match API naming conventions with Uppy
3. Replicate event names and lifecycle hooks
4. Document any deviations from Uppy (with reasoning)

**Example - Uppy has `addFile()`, Fluppy should have `addFile()` (not `addNewFile()` or `insertFile()`)**

### 2. Use Dart Best Practices

- **Streams** instead of EventEmitter (Dart-idiomatic)
- **Sealed classes** for type-safe events
- **Abstract classes** for extensibility
- **async/await** for asynchronous operations
- **Extension methods** for utility functions
- **Null safety** properly enforced
- **dartdoc comments** on all public APIs

### 3. Package Design

- Keep public API **minimal** (export from `lib/fluppy.dart` only)
- Implementation details in `lib/src/` (not exported)
- **Semantic versioning** (breaking changes = major version)
- Backwards compatibility when possible

### 4. Testing Requirements

- **Unit tests** for all public APIs
- **Integration tests** for complete workflows
- **Mock uploaders** for testing without network
- **Example app** demonstrates real usage
- Aim for **high coverage** (>80%)

### 5. Documentation Standards

- **dartdoc comments** on all public APIs
- **Code examples** in documentation
- **README.md** kept current with features
- **CHANGELOG.md** updated with every change
- Reference **Uppy docs** where relevant

---

## Implementation Workflow

### For New Features

1. **Read `docs/uppy-study.md`** - Understand Uppy's implementation
2. **Create a plan** - Follow `docs/plan.md` process
3. **Get approval** - Wait for user confirmation
4. **Implement** - Follow `docs/implement.md` process with approved plan
5. **Test** - Write comprehensive tests
6. **Document** - Update README, dartdocs, examples
7. **Update changelog** - Document changes

### For Bug Fixes

1. **Understand the issue** - Read relevant code and tests
2. **Check Uppy behavior** - Ensure alignment with Uppy
3. **Fix the bug** - Minimal changes
4. **Add test** - Prevent regression
5. **Update changelog** - Document fix

### For Refactoring

1. **Verify need** - Ensure improvement is valuable
2. **Plan changes** - Use `docs/plan.md` if complex
3. **Maintain API compatibility** - Don't break existing users
4. **Test thoroughly** - Ensure no behavior changes
5. **Document** - Explain reasoning

---

## Architecture Overview

### Core Classes

**`Fluppy`** (`lib/src/core/fluppy.dart`)
- Main orchestrator class
- Manages files, uploaders, and lifecycle
- Emits events via Streams
- Public API: `addFile()`, `upload()`, `pauseAll()`, etc.

**`Uploader`** (`lib/src/core/uploader.dart`)
- Abstract base class for all uploaders
- Defines upload contract
- Implementations: `S3Uploader`, `TusUploader` (planned), etc.

**`FluppyFile`** (`lib/src/core/fluppy_file.dart`)
- Represents a file to be uploaded
- Supports multiple sources: path, bytes, stream
- Tracks status, progress, metadata

**`FluppyEvent`** (`lib/src/core/events.dart`)
- Sealed class hierarchy for type-safe events
- Events: `FileAdded`, `UploadProgress`, `UploadComplete`, etc.
- Emitted via `fluppy.events` stream

### Data Flow

```
┌─────────────────────────────────────────┐
│         User Code (Flutter App)         │
└───────────────┬─────────────────────────┘
                │
                │ addFile(), upload()
                ▼
┌─────────────────────────────────────────┐
│     Fluppy (Core Orchestrator)          │
│  - File management                       │
│  - Event emission                        │
│  - Lifecycle control                     │
└───────────────┬─────────────────────────┘
                │
                │ upload() call
                ▼
┌─────────────────────────────────────────┐
│   Uploader (S3Uploader, TusUploader)    │
│  - Protocol-specific upload logic        │
│  - Progress tracking                     │
│  - Error handling                        │
└───────────────┬─────────────────────────┘
                │
                │ HTTP requests
                ▼
┌─────────────────────────────────────────┐
│      Backend (S3, Tus server, etc.)     │
└─────────────────────────────────────────┘
```

### Event System

Fluppy uses **Streams** and **Sealed Classes** for events:

```dart
// Listen to all events
fluppy.events.listen((event) {
  switch (event) {
    case FileAdded(:final file):
      print('File added: ${file.name}');
    case UploadProgress(:final fileId, :final bytesUploaded, :final bytesTotal):
      print('Progress: $bytesUploaded / $bytesTotal');
    case UploadComplete(:final fileId, :final response):
      print('Upload complete: ${response.url}');
    case UploadError(:final fileId, :final error):
      print('Error: $error');
  }
});
```

---

## Uppy Feature Mapping

### Current Status

| Uppy Feature | Fluppy Status | Implementation |
|--------------|---------------|----------------|
| Core orchestrator | ✅ Complete | `lib/src/core/fluppy.dart` |
| Event system | ✅ Complete | `lib/src/core/events.dart` |
| File management | ✅ Complete | `lib/src/core/fluppy_file.dart` |
| S3 uploader (single) | ✅ Complete | `lib/src/s3/s3_uploader.dart` |
| S3 uploader (multipart) | ✅ Complete | `lib/src/s3/s3_uploader.dart` |
| AWS Signature V4 | ✅ Complete | `lib/src/s3/aws_signature_v4.dart` |
| Pause/Resume | ✅ Complete | Core + S3 |
| Retry logic | ✅ Complete | Core |
| Progress tracking | ✅ Complete | Core + Uploaders |
| Tus uploader | ❌ Missing | Planned |
| XHR/HTTP uploader | ❌ Missing | Planned |
| Preprocessing pipeline | ❌ Missing | Planned |
| Postprocessing pipeline | ❌ Missing | Planned |
| File restrictions | ❌ Missing | Planned |
| Remote sources | ❌ Missing | Out of scope? |
| UI components | ❌ Missing | Intentionally excluded |

### Priority Features to Add

1. **Preprocessing/Postprocessing** - Core to Uppy's architecture
2. **Tus Uploader** - Most requested resumable upload protocol
3. **File Restrictions** - Validation (size, type, count)
4. **HTTP/XHR Uploader** - Basic uploader for simple backends

---

## Common Patterns

### Adding a New Uploader

1. Create directory: `lib/src/[uploader_name]/`
2. Extend `Uploader` abstract class
3. Create options class (e.g., `TusOptions`)
4. Create types/models (e.g., `TusTypes`)
5. Implement `upload()` method
6. Emit progress events
7. Handle pause/resume/cancel
8. Write tests
9. Update README and examples

### Adding Core Functionality

1. Modify `lib/src/core/fluppy.dart`
2. Add new events to `lib/src/core/events.dart` if needed
3. Ensure API matches Uppy convention
4. Write unit tests
5. Update integration tests
6. Update README
7. Update `docs/uppy-study.md` if documenting gap

### Modifying Public API

1. **Check semver impact** - Is this a breaking change?
2. **Consider backwards compatibility** - Can we avoid breaking?
3. **Update all affected code** - Core, uploaders, tests, examples
4. **Update documentation** - README, dartdocs
5. **Update CHANGELOG** - Note breaking changes clearly

---

## Testing Strategy

### Unit Tests

Test individual classes and methods in isolation:

```dart
test('addFile adds file to collection', () {
  final fluppy = Fluppy(uploader: MockUploader());
  final file = FluppyFile(/* ... */);

  fluppy.addFile(file);

  expect(fluppy.files, contains(file));
});
```

### Integration Tests

Test complete workflows:

```dart
test('upload completes successfully', () async {
  final fluppy = Fluppy(uploader: MockUploader());
  fluppy.addFile(file);

  final events = <FluppyEvent>[];
  fluppy.events.listen(events.add);

  await fluppy.upload();

  expect(events, contains(isA<UploadComplete>()));
});
```

### Mock Uploaders

Use mocks for testing without network:

```dart
class MockUploader extends Uploader {
  @override
  Future<UploadResponse> upload(FluppyFile file, CancellationToken token) async {
    // Simulate upload
    await Future.delayed(Duration(milliseconds: 100));
    return UploadResponse(url: 'https://mock.url/file.jpg');
  }
}
```

---

## Documentation

### dartdoc Comments

All public APIs must have dartdoc comments:

```dart
/// Adds a file to the upload queue.
///
/// The [file] will be validated against any configured restrictions
/// before being added. If validation fails, an error event will be emitted.
///
/// Example:
/// ```dart
/// final file = FluppyFile(
///   name: 'photo.jpg',
///   source: FileSourceType.path,
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
- Feature list
- Installation instructions
- Quick start example
- API overview
- Link to full documentation

### CHANGELOG

Follow [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
## [0.2.0] - 2026-01-15

### Added
- Tus uploader support for resumable uploads
- File size and type restrictions

### Changed
- Improved error messages for S3 uploads

### Fixed
- Multipart upload resume issue with large files
```

---

## Common Gotchas

### 1. Streams vs EventEmitter

**Uppy** uses EventEmitter (Node.js style):
```javascript
uppy.on('upload-progress', (file, progress) => { })
```

**Fluppy** uses Streams (Dart style):
```dart
fluppy.events.listen((event) {
  if (event is UploadProgress) { }
})
```

### 2. Sealed Classes for Events

Use **sealed classes** for type-safe event handling:

```dart
sealed class FluppyEvent {}

class UploadProgress extends FluppyEvent {
  final String fileId;
  final int bytesUploaded;
  final int bytesTotal;
}
```

Benefits:
- Exhaustive switch statements
- Compile-time safety
- Pattern matching

### 3. Async File Operations

Dart's `dart:io` is async by nature:

```dart
// Read file
final file = File(path);
final bytes = await file.readAsBytes();

// Stream file
final stream = file.openRead();
```

### 4. Platform Differences

Fluppy should work on:
- **Flutter mobile** (iOS, Android)
- **Flutter web** (with dart:html bridge)
- **Flutter desktop** (Windows, Mac, Linux)
- **Dart CLI/server** (with dart:io)

Consider platform differences when implementing features.

---

## Resources

### Official Documentation
- [Uppy Documentation](https://uppy.io/docs/)
- [Uppy GitHub](https://github.com/transloadit/uppy)
- [Dart Documentation](https://dart.dev/guides)
- [Flutter Documentation](https://flutter.dev/docs)

### Internal Documentation
- `docs/uppy-study.md` - Comprehensive Uppy reference
- `docs/plan.md` - Implementation planning guide
- `docs/implement.md` - Implementation execution guide
- `docs/research.md` - Codebase research guide
- `README.md` - Package overview

### Related Standards
- [Tus Protocol](https://tus.io/protocols/resumable-upload.html)
- [AWS S3 Multipart Upload](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html)

---

## Getting Help

If you encounter issues or have questions:

1. **Read the docs** - Start with `docs/uppy-study.md`
2. **Check existing code** - Look at S3Uploader as reference
3. **Ask the user** - When design decisions are needed
4. **Document your findings** - Use `docs/research.md` process

---

## Summary

**Remember:**
1. ✅ Always read `docs/uppy-study.md` before implementing features
2. ✅ Match Uppy's API and naming conventions
3. ✅ Use Dart best practices (Streams, sealed classes)
4. ✅ Write comprehensive tests
5. ✅ Document everything (dartdocs, README, CHANGELOG)
6. ✅ Follow the plan → implement → test → document workflow

**Goal**: Build a Dart package that's as good as Uppy, but Dart-native!
