# Create Implementation Plan for Fluppy

You are tasked with creating detailed implementation plans through an interactive, iterative process for the **Fluppy Flutter package**. You should be skeptical, thorough, and work collaboratively with the user to produce high-quality technical specifications.

## Context: What is Fluppy?

Fluppy is a **Flutter/Dart package for file uploads**, inspired by [Uppy.js](https://uppy.io/). The goal is to achieve **1:1 feature parity** with Uppy while following Dart/Flutter best practices.

**Key Reference**: Always consult [`docs/uppy-study.md`](uppy-study.md) for Uppy's architecture, API, and patterns before planning any feature.

---

## Initial Response

When this command is invoked:

1. **Check if parameters were provided**:
   - If a file path or task description was provided, skip the default message
   - Immediately read any provided files FULLY
   - Begin the research process

2. **Check for Uppy.js references**:
   - If the user mentions Uppy features or wants to replicate Uppy behavior
   - **READ** `docs/uppy-study.md` first to understand Uppy's implementation
   - Use that as the source of truth for the feature design. Also look online to make sure the knowledge os always up to date. If you find something is missing, update the `docs/uppy-study.md` accoerdingly.

3. **If no parameters provided**, respond with:

```
I'll help you create a detailed implementation plan for Fluppy. Let me start by understanding what we're building.

Please provide:
1. The feature/task description (or reference to a spec file)
2. Any relevant Uppy.js features you want to replicate
3. Any specific constraints or requirements for the Dart/Flutter implementation

I'll analyze this information and work with you to create a comprehensive plan.

Tip: I'll automatically reference docs/uppy-study.md to ensure alignment with Uppy's architecture.
```

Then wait for the user's input.

---

## Process Steps

### Step 1: Context Gathering & Initial Analysis

1. **Read all mentioned files immediately and FULLY**:
   - Task specification files
   - `docs/uppy-study.md` for Uppy reference
   - Existing implementation files
   - **IMPORTANT**: Use the Read tool WITHOUT limit/offset parameters
   - **CRITICAL**: Read these files yourself before spawning agents

2. **Understand Uppy's approach**:
   - How does Uppy implement this feature?
   - What API does Uppy expose?
   - What patterns does Uppy follow?
   - This ensures we maintain 1:1 parity

3. **Research the current codebase**:
   - Read existing related files (`lib/src/core/`, `lib/src/s3/`, etc.)
   - Understand current architecture and patterns
   - Identify what already exists vs what's missing

4. **Analyze and verify understanding**:
   - Cross-reference Uppy's design with Dart/Flutter capabilities
   - Identify Dart-specific adaptations needed (e.g., Streams vs EventEmitter)
   - Note assumptions that need verification

5. **Present informed understanding and focused questions**:

   ```
   Based on the task and my research of Uppy's approach, I understand we need to [accurate summary].

   In Uppy, this works by:
   - [Uppy's implementation detail with reference]
   - [Key pattern or design]

   For Fluppy, I propose:
   - [Dart/Flutter adaptation]
   - [Implementation approach]

   Questions:
   - [Specific technical question]
   - [Design preference that affects implementation]
   ```

### Step 2: Research & Discovery

After getting initial clarifications:

1. **Create a research todo list** using TodoWrite to track exploration tasks

2. **Read existing implementation files**:
   - `lib/src/core/fluppy.dart` - Core orchestrator
   - `lib/src/core/uploader.dart` - Abstract uploader
   - `lib/src/core/fluppy_file.dart` - File model
   - `lib/src/core/events.dart` - Event system
   - `lib/src/s3/` - S3 implementation example
   - `test/` - Existing tests

3. **Verify Uppy alignment**:
   - Compare proposed approach with Uppy's implementation
   - Ensure API naming matches Uppy conventions
   - Check event names and lifecycle hooks

4. **Present findings and design options**:

   ```
   Based on my research, here's what I found:

   **Uppy's Approach:**
   - [How Uppy implements this feature]
   - [Key API methods and options]

   **Current Fluppy State:**
   - [What's already implemented]
   - [What needs to be added]

   **Design Options:**
   1. [Option A] - [pros/cons, Uppy alignment]
   2. [Option B] - [pros/cons, Uppy alignment]

   **Recommendation:** [Option X] because [reasoning]

   Questions:
   - [Technical decision needed]
   ```

### Step 3: Plan Structure Development

Once aligned on approach:

1. **Create initial plan outline**:

   ```
   Here's my proposed plan structure:

   ## Overview
   [1-2 sentence summary, reference to Uppy feature]

   ## Implementation Phases:
   1. [Phase name] - [what it accomplishes]
   2. [Phase name] - [what it accomplishes]
   3. [Phase name] - [what it accomplishes]

   Does this phasing make sense? Should I adjust the order or granularity?
   ```

2. **Get feedback on structure** before writing details

### Step 4: Detailed Plan Writing

After structure approval:

1. **Write the plan** to `docs/plans/YYYYMMDD_{descriptive_name}.md`
   - Date prefix format: `YYYYMMDD` (e.g., `20260111`)
   - Example: `20260111_tus-uploader-implementation.md`

2. **Use this template structure**:

```markdown
# [Feature/Task Name] Implementation Plan

| Field | Value |
|-------|-------|
| **Created** | [YYYY-MM-DD] |
| **Last Updated** | [YYYY-MM-DD] |
| **Uppy Reference** | [Link to relevant Uppy docs] |
| **Status** | Draft / Approved / In Progress / Complete |

## Overview

[Brief description of what we're implementing and why]

**Uppy Equivalent**: [Link to Uppy feature/plugin with brief description]

## Current State Analysis

### What Exists
- [Current implementation with file references]
- [Related features already in place]

### What's Missing
- [Feature X not yet implemented]
- [API Y needs to be added]

### Key Discoveries
- [Important finding with file:line reference]
- [Pattern to follow from existing code]
- [Uppy pattern we need to replicate]

## Desired End State

[A specification of the desired end state after this plan is complete]

**Success Criteria:**
- [ ] Feature works as Uppy does
- [ ] API matches Uppy naming conventions
- [ ] All tests pass
- [ ] Example demonstrates usage
- [ ] Documentation is updated

## Uppy Alignment

### Uppy's Implementation
[How Uppy implements this feature with code examples or architectural notes]

### Fluppy Adaptation Strategy
[How we'll adapt Uppy's approach to Dart/Flutter]

**API Mapping:**
| Uppy API | Fluppy API | Notes |
|----------|------------|-------|
| `uppy.method()` | `fluppy.method()` | Direct port |
| `uppy.on('event')` | `fluppy.events.listen()` | Stream-based |

**Event Mapping:**
| Uppy Event | Fluppy Event | Notes |
|------------|--------------|-------|
| `'event-name'` | `EventClass` | Sealed class |

## What We're NOT Doing

[Explicitly list out-of-scope items to prevent scope creep]

## Implementation Approach

[High-level strategy and reasoning]

---

## Phase 1: [Descriptive Name]

### Overview
[What this phase accomplishes]

### Files to Modify

#### 1. `lib/src/core/fluppy.dart`
**Changes**: [Summary of changes]

```dart
// Specific code to add/modify
class Fluppy {
  // New method example
  Future<void> newMethod() async {
    // Implementation
  }
}
```

**Why**: [Reasoning for changes, Uppy reference]

#### 2. `lib/src/core/events.dart`
**Changes**: Add new event types

```dart
sealed class FluppyEvent {}

class NewEvent extends FluppyEvent {
  final String fileId;
  // ...
}
```

### New Files to Create

#### 1. `lib/src/[category]/[name].dart`
**Purpose**: [What this file does]

```dart
// Key interfaces or classes to implement
```

### Tests to Add

#### 1. `test/[name]_test.dart`
**Purpose**: Test new functionality

```dart
// Key test scenarios
```

### Success Criteria
- [ ] Code compiles without errors
- [ ] All new tests pass: `dart test`
- [ ] Existing tests still pass
- [ ] Example demonstrates feature
- [ ] Code follows Dart conventions: `dart format`
- [ ] No linter warnings: `dart analyze`

---

## Phase 2: [Descriptive Name]

[Similar structure to Phase 1]

---

## Testing Strategy

### Unit Tests
- [Test scenario 1]
- [Test scenario 2]

### Integration Tests
- [End-to-end scenario 1]
- [End-to-end scenario 2]

### Manual Testing
- [Manual verification step 1]
- [Manual verification step 2]

## Documentation Updates

### API Documentation
- [ ] Update `README.md` with new feature
- [ ] Add dartdoc comments to public APIs
- [ ] Update `example/example.dart` with usage

### Alignment Documentation
- [ ] Update `docs/uppy-study.md` if needed
- [ ] Document any deviations from Uppy

## Migration Guide (if applicable)

[If this changes existing APIs, document migration path]

---

## References

- **Uppy Documentation**: [Link to relevant Uppy docs]
- **Uppy Source**: [Link to GitHub implementation]
- **Uppy Study**: `docs/uppy-study.md`
- **Related PRs/Issues**: [Links if any]

## Open Questions

[Any questions to resolve before implementation - should be empty in final plan]

---

## Implementation Notes

[Any additional context, gotchas, or considerations]
```

### Step 5: Review

1. **Present the draft plan location**:

```
I've created the implementation plan at:
`docs/plans/[filename].md`

Please review it and let me know:
- Does it align with Uppy's approach?
- Are the phases properly scoped?
- Are the success criteria specific enough?
- Any technical details that need adjustment?
```

2. **Iterate based on feedback** - be ready to:
   - Adjust technical approach
   - Add missing phases
   - Clarify Uppy alignment
   - Add/remove scope items

3. **Continue refining** until the user is satisfied

---

## Important Guidelines

### 1. Uppy Alignment is Critical

- **Always check** `docs/uppy-study.md` first
- **Match API naming** with Uppy conventions
- **Replicate patterns** where appropriate
- **Document deviations** when Dart/Flutter requires different approach
- **Verify events** match Uppy's event system

### 2. Dart/Flutter Best Practices

- Use **streams** instead of EventEmitter
- Use **sealed classes** for type-safe events
- Follow **Dart naming conventions** (lowerCamelCase, UpperCamelCase)
- Use **async/await** for asynchronous operations
- Leverage **extension methods** when appropriate
- Use **null safety** properly

### 3. Package Considerations

- Keep public API **minimal and focused**
- Export only what's needed from `lib/fluppy.dart`
- Use `lib/src/` for implementation details
- Consider **breaking changes** carefully (semver)
- Think about **backwards compatibility**

### 4. Testing Requirements

- **Unit tests** for all public APIs
- **Integration tests** for complete workflows
- **Mock uploaders** for testing without network
- **Example app** demonstrates real usage
- Aim for **high test coverage**

### 5. Documentation Standards

- **dartdoc comments** on all public APIs
- **Code examples** in documentation
- **README.md** kept up to date
- **CHANGELOG.md** updated with changes
- Reference **Uppy docs** where relevant

### 6. Be Interactive

- Don't write the full plan in one shot
- Get buy-in at each major step
- Allow course corrections
- Work collaboratively

### 7. Be Thorough

- Read all context files COMPLETELY before planning
- Research actual Uppy implementation
- Include specific file paths and line numbers
- Write measurable success criteria

### 8. No Open Questions in Final Plan

- If you encounter open questions during planning, STOP
- Research or ask for clarification immediately
- Do NOT write the plan with unresolved questions
- The implementation plan must be complete and actionable
- Every decision must be made before finalizing the plan

### 9. Track Progress

- Use TodoWrite to track planning tasks
- Update todos as you complete research
- Mark planning tasks complete when done

---

## Package Structure Reference

```
fluppy/
├── lib/
│   ├── fluppy.dart              # Public API exports
│   └── src/
│       ├── core/
│       │   ├── fluppy.dart      # Core orchestrator
│       │   ├── uploader.dart    # Abstract uploader base
│       │   ├── fluppy_file.dart # File model
│       │   └── events.dart      # Event system
│       ├── s3/
│       │   ├── s3_uploader.dart # S3 implementation
│       │   ├── s3_options.dart  # S3 configuration
│       │   ├── s3_types.dart    # S3 types
│       │   └── aws_signature_v4.dart # AWS signing
│       ├── tus/                 # Tus uploader (future)
│       ├── http/                # HTTP uploader (future)
│       └── [other uploaders]/
├── test/
│   ├── fluppy_test.dart         # Core tests
│   ├── fluppy_file_test.dart   # File tests
│   └── [uploader]_test.dart    # Uploader-specific tests
├── example/
│   └── example.dart             # Usage examples
├── docs/
│   ├── uppy-study.md            # Uppy reference guide
│   ├── plans/                   # Implementation plans
│   └── research/                # Research documents
├── pubspec.yaml                 # Package metadata
├── README.md                    # Package documentation
├── CHANGELOG.md                 # Version history
└── LICENSE                      # MIT License
```

---

## Common Planning Scenarios

### Adding a New Uploader (e.g., Tus, HTTP)

1. Read `docs/uppy-study.md` section on the uploader
2. Study existing `S3Uploader` as reference
3. Plan to extend `Uploader` abstract class
4. Define options class (like `S3Options`)
5. Define types/models (like `S3Types`)
6. Implement upload lifecycle methods
7. Add tests and example
8. Update README

### Adding Core Feature (e.g., Preprocessing)

1. Read `docs/uppy-study.md` on Uppy's pipeline
2. Study existing event system and lifecycle
3. Plan modifications to `Fluppy` core class
4. Define new event types
5. Add processor registration methods
6. Implement execution logic
7. Add tests and documentation
8. Update Uppy alignment docs

### Adding Configuration Option

1. Check Uppy's equivalent option
2. Add to appropriate options class
3. Update constructor and validation
4. Implement behavior change
5. Add tests for new behavior
6. Document in README and dartdoc

---

## Example Interaction Flow

```
User: I want to add the Tus uploader to Fluppy
Assistant: I'll help create a plan for adding Tus uploader support. Let me first read the Uppy study document to understand how Uppy implements Tus...

[Reads docs/uppy-study.md]

Based on Uppy's Tus implementation, I understand that:
- Tus is the resumable upload protocol
- Uppy wraps the tus-js-client library
- Key features: automatic resume, chunk-based upload, exponential backoff

For Fluppy, we'll need to:
1. Find or create a Dart Tus client library
2. Extend the Uploader abstract class
3. Implement pause/resume based on Tus protocol
4. Match Uppy's configuration options

Let me research existing Dart Tus libraries...

[Research continues with interactive questions and plan development]
```

---

## After Plan Approval

**IMPORTANT**: Once the user approves the plan, **DO NOT** automatically start implementing it. Wait for the user to provide explicit instructions to begin implementation.

The planning phase is complete when the plan is written and approved. Implementation is a separate phase that requires explicit user initiation.

---

## User Input

$ARGUMENTS
