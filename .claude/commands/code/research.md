# Research Codebase - Fluppy

You are tasked with conducting comprehensive research across the **Fluppy Flutter package** codebase to answer user questions by thoroughly exploring the implementation and synthesizing findings.

## Context: What is Fluppy?

Fluppy is a **Flutter/Dart package for file uploads**, inspired by [Uppy.js](https://uppy.io/). The goal is to achieve **1:1 feature parity** with Uppy while following Dart/Flutter best practices.

**Key Reference**: Always consult [`docs/uppy-study.md`](uppy-study.md) for Uppy's architecture and patterns.

---

## Initial Setup

When this command is invoked, respond with:

```
I'm ready to research the Fluppy codebase. Please provide your research question or area of interest, and I'll analyze it thoroughly.

I can help you understand:
- Current implementation details
- How features work (architecture, data flow)
- Uppy alignment and gaps
- Best practices and patterns
- Integration strategies
```

Then wait for the user's research query.

---

## Steps to Follow After Receiving the Research Query

### Step 1: Read Mentioned Files First

If the user mentions specific files, read them FULLY first:

- **IMPORTANT**: Use the Read tool WITHOUT limit/offset parameters
- **CRITICAL**: Read these files yourself before spawning any research
- Common files to read:
  - `docs/uppy-study.md` - Uppy reference
  - `lib/fluppy.dart` - Public API
  - `lib/src/core/` - Core implementation
  - `lib/src/[uploader]/` - Uploader implementations
  - `test/` - Test files
  - `example/example.dart` - Usage examples

### Step 2: Analyze and Decompose the Research Question

- Break down the user's query into specific areas
- Think about:
  - **What** is being asked (feature, architecture, pattern)?
  - **Where** in the codebase is this implemented?
  - **How** does Uppy handle this (if relevant)?
  - **Why** is this designed this way?
- Create a research plan using TodoWrite to track subtasks

### Step 3: Research Strategy

For a Dart package like Fluppy, focus on:

**Core Package Structure:**
| Component | Location | Purpose |
|-----------|----------|---------|
| Public API | `lib/fluppy.dart` | Exported public interface |
| Core Classes | `lib/src/core/` | Orchestrator, base classes, events |
| Uploaders | `lib/src/[uploader]/` | Implementation-specific code |
| Tests | `test/` | Unit and integration tests |
| Examples | `example/` | Usage demonstrations |
| Documentation | `docs/`, `README.md` | Guides and references |

**Key Files to Understand:**
- `lib/src/core/fluppy.dart` - Main orchestrator class
- `lib/src/core/uploader.dart` - Abstract uploader base
- `lib/src/core/fluppy_file.dart` - File model
- `lib/src/core/events.dart` - Event system (sealed classes)
- `lib/src/s3/s3_uploader.dart` - Example uploader implementation
- `docs/uppy-study.md` - Uppy alignment reference

### Step 4: Execute Research

**For Implementation Questions:**
1. Read the relevant source files
2. Trace the code flow (method calls, data transformations)
3. Identify key patterns and architectures
4. Note public APIs and their usage
5. Check tests for expected behavior

**For Uppy Alignment Questions:**
1. Read `docs/uppy-study.md` for Uppy's approach
2. Compare with Fluppy's implementation
3. Identify matches and gaps
4. Note naming conventions and API similarities

**For Architecture Questions:**
1. Understand the overall structure
2. Identify key abstractions and patterns
3. Trace data flow through the system
4. Note design decisions and trade-offs

### Step 5: Synthesize Findings

Compile findings with:
- **Specific code references** (`file.dart:line`)
- **Uppy comparisons** (how it aligns or differs)
- **Patterns used** (abstract classes, streams, sealed classes)
- **Architectural decisions** (why certain approaches were taken)

### Step 6: Generate Research Document

Write the research document to: `docs/research/YYYY-MM-DD_topic.md`

Use this structure:

```markdown
---
date: [Current date in ISO format]
topic: "[User's Question/Topic]"
tags: [research, fluppy, relevant-tags]
status: complete
---

# Research: [User's Question/Topic]

## Research Question

[The question being addressed]

## Summary

[High-level findings answering the question - 2-3 paragraphs]

**Key Takeaways:**
- [Main finding 1]
- [Main finding 2]
- [Main finding 3]

## Detailed Findings

### Current Implementation

[Detailed analysis of how Fluppy currently handles this]

**Code References:**
- `lib/src/core/fluppy.dart:45-67` - Main orchestration logic
- `lib/src/core/events.dart:12` - Event definition

**Key Patterns:**
- [Pattern 1 with explanation]
- [Pattern 2 with explanation]

### Uppy Alignment

[How this compares to Uppy's approach]

**What Matches:**
- [Feature X matches Uppy's implementation]
- [API Y follows Uppy naming]

**What Differs:**
- [Difference X because Dart/Flutter requires...]
- [Difference Y is an enhancement]

**Gaps:**
- [Missing feature A from Uppy]
- [Missing API B from Uppy]

### Architecture Insights

[Design patterns, architectural decisions, trade-offs]

**Design Decisions:**
- [Decision 1 and reasoning]
- [Decision 2 and reasoning]

**Trade-offs:**
- [Trade-off 1: benefit vs cost]

### Data Flow

[If applicable, trace data flow through the system]

```
User Action → Fluppy.method() → Uploader.upload() → Events
```

### Examples

[Code examples demonstrating the feature]

```dart
// Example usage
final fluppy = Fluppy(uploader: S3Uploader(options));
fluppy.addFile(file);
await fluppy.upload();
```

## Testing Coverage

[What tests exist for this feature]

**Test Files:**
- `test/fluppy_test.dart` - Core functionality tests
- `test/[feature]_test.dart` - Feature-specific tests

**Coverage Gaps:**
- [Missing test scenario A]
- [Missing test scenario B]

## Related Features

[Connections to other features or components]

- [Related feature A] - [How it connects]
- [Related feature B] - [How it connects]

## Recommendations

[If applicable, suggestions based on findings]

1. [Recommendation 1 with reasoning]
2. [Recommendation 2 with reasoning]

## References

- Uppy Study: `docs/uppy-study.md`
- Source Files: [List of key files examined]
- Uppy Docs: [Relevant Uppy documentation links]
- Tests: [Relevant test files]

## Follow-up Questions

[Questions that arose during research, if any]
```

### Step 7: Handle Follow-up Questions

If the user has follow-up questions:

- Append to the same research document
- Add a new section: `## Follow-up Research [date]`
- Continue investigating and updating the document

---

## Important Notes

### Research Efficiency

- **Read files directly** for specific code questions
- **Trace code paths** through multiple files
- **Check tests** for expected behavior
- **Verify against Uppy** for alignment questions

### Accuracy

- Always provide **file:line references** for claims
- Quote relevant code snippets when helpful
- Distinguish between **facts** (from code) and **interpretations**
- Note **assumptions** explicitly

### Uppy Alignment

- Reference `docs/uppy-study.md` for Uppy patterns
- Compare API naming and structure
- Note where Dart/Flutter requires different approaches
- Identify feature gaps

### Dart/Flutter Specifics

When researching, consider:

| Dart/Flutter Concept | Fluppy Usage | Uppy Equivalent |
|---------------------|--------------|-----------------|
| Streams | Event broadcasting | EventEmitter |
| Sealed Classes | Type-safe events | Event strings |
| Abstract Classes | Uploader base | BasePlugin |
| async/await | Asynchronous operations | Promises |
| Extension Methods | Utility functions | Helper functions |

---

## Common Research Scenarios

### "How does [feature] work?"

1. Read `docs/uppy-study.md` to understand Uppy's approach
2. Read relevant Fluppy source files
3. Trace the code flow from API to implementation
4. Document the data flow and key methods
5. Compare with Uppy's implementation

### "What's missing compared to Uppy?"

1. Read `docs/uppy-study.md` section on the feature
2. Check Fluppy's implementation for equivalent functionality
3. List what's implemented, what's missing
4. Note any deviations or enhancements
5. Provide feature parity checklist

### "How do I implement [new feature]?"

1. Research Uppy's implementation (from study doc)
2. Identify similar patterns in existing Fluppy code
3. Determine what needs to be added/modified
4. Outline implementation approach
5. This research feeds into a plan

### "Why is it designed this way?"

1. Analyze the architecture and patterns
2. Consider Dart/Flutter constraints
3. Compare with Uppy's design
4. Identify trade-offs and benefits
5. Document reasoning

---

## Example Research Flow

```
User: How does the event system work in Fluppy?