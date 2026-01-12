# Uppy Pause, Resume, and Cancellation - Deep Dive Analysis

> **Purpose**: This document provides a comprehensive analysis of how Uppy.js implements pause, resume, and cancellation functionality. This research is based on the Uppy source code (cloned from https://github.com/transloadit/uppy) and serves as a reference for implementing similar functionality in Fluppy.

**Date**: 2026-01-12
**Uppy Version**: Latest (as of Jan 2026)
**Source Files Analyzed**:
- `packages/@uppy/core/src/Uppy.ts`
- `packages/@uppy/core/src/EventManager.ts`
- `packages/@uppy/tus/src/index.ts`
- `packages/@uppy/aws-s3/src/index.ts`
- `packages/@uppy/aws-s3/src/MultipartUploader.ts`
- `packages/@uppy/xhr-upload/src/index.ts`
- `packages/@uppy/utils/src/RateLimitedQueue.ts`

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Core State Management](#core-state-management)
3. [Event System](#event-system)
4. [Core API Methods](#core-api-methods)
5. [EventManager - Event Coordination](#eventmanager---event-coordination)
6. [RateLimitedQueue - Concurrent Upload Management](#ratelimitedqueue---concurrent-upload-management)
7. [Tus Uploader Implementation](#tus-uploader-implementation)
8. [AWS S3 Uploader Implementation](#aws-s3-uploader-implementation)
9. [XHR Uploader Implementation](#xhr-uploader-implementation)
10. [Key Design Patterns](#key-design-patterns)
11. [Comparison Summary](#comparison-summary)
12. [Fluppy Implementation Recommendations](#fluppy-implementation-recommendations)

---

## Architecture Overview

Uppy's pause/resume/cancel functionality is a **layered architecture** with responsibilities split across multiple components:

```
┌─────────────────────────────────────────────────────────────┐
│                     User Application                        │
│         (Calls pauseAll(), resumeAll(), cancelAll())        │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                      Uppy Core                              │
│  - State Management (file.isPaused, capabilities)           │
│  - Event Emission (pause-all, resume-all, cancel-all)       │
│  - File State Updates                                       │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    EventManager                             │
│  - Per-file event filtering (onPause, onPauseAll, etc.)     │
│  - Lifecycle management (remove all listeners)              │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                 Uploader Plugins                            │
│  - Tus: tus.Upload.abort()/start(), RateLimitedQueue       │
│  - S3: MultipartUploader.pause()/start(), AbortController  │
│  - XHR: AbortController, RateLimitedQueue                   │
└─────────────────────────────────────────────────────────────┘
```

### Key Principles

1. **Separation of Concerns**: Core handles state/events, uploaders handle protocol-specific logic
2. **Event-Driven**: Core emits events, uploaders listen and react
3. **Capability-Based**: `capabilities.resumableUploads` indicates if pause/resume is supported
4. **Queue-Based**: RateLimitedQueue manages concurrent uploads and pause/resume

---

## Core State Management

### File State Properties

Each file in Uppy's state can have these pause/resume related properties:

```typescript
interface UppyFile {
  id: string;
  isPaused?: boolean;        // Whether file upload is paused
  error?: string;            // Error message if upload failed
  progress: {
    uploadStarted?: number;  // Timestamp when upload started
    uploadComplete: boolean; // Whether upload finished
    bytesUploaded: number;
    bytesTotal: number;
    percentage: number;
  };
  // Uploader-specific state (for resume capability)
  tus?: { uploadUrl?: string };           // Tus resume URL
  s3Multipart?: { key: string; uploadId: string }; // S3 multipart state
}
```

### Capabilities State

```typescript
interface Capabilities {
  uploadProgress: boolean;      // Can track progress
  individualCancellation: boolean; // Can cancel single files
  resumableUploads: boolean;    // Can pause/resume uploads
}
```

### State Update Patterns

Uppy uses **immutable state updates**:

```typescript
// Single file pause state update
setFileState(fileID: string, state: Partial<UppyFile>) {
  this.patchFilesState({ [fileID]: state });
}

// Batch update for pause/resume all
pauseAll(): void {
  const updatedFiles = { ...this.getState().files };
  const inProgressFiles = Object.keys(updatedFiles).filter((file) => {
    return (
      !updatedFiles[file].progress.uploadComplete &&
      updatedFiles[file].progress.uploadStarted
    );
  });

  inProgressFiles.forEach((file) => {
    const updatedFile = { ...updatedFiles[file], isPaused: true };
    updatedFiles[file] = updatedFile;
  });

  this.setState({ files: updatedFiles });
  this.emit('pause-all');
}
```

---

## Event System

### Pause/Resume/Cancel Events

| Event | When Emitted | Payload | Handler Responsibility |
|-------|--------------|---------|------------------------|
| `upload-pause` | Single file pause toggle | `(file, isPaused: boolean)` | Uploader pauses/resumes specific file |
| `pause-all` | All files paused | `()` | Uploaders pause all active uploads |
| `resume-all` | All files resumed | `()` | Uploaders resume all paused uploads |
| `cancel-all` | All uploads cancelled | `()` | Uploaders abort and cleanup all uploads |
| `upload-retry` | Single file retry | `(file)` | Uploader retries specific file |
| `retry-all` | All failed files retry | `(files[])` | Uploaders retry all failed files |

### Event Flow Example: Pause All

```
User calls: uppy.pauseAll()
                │
                ▼
┌───────────────────────────────────────┐
│ 1. Core updates file states           │
│    file.isPaused = true               │
│    (for all in-progress files)        │
└───────────────────────────────────────┘
                │
                ▼
┌───────────────────────────────────────┐
│ 2. Core emits 'pause-all' event       │
└───────────────────────────────────────┘
                │
                ▼
┌───────────────────────────────────────┐
│ 3. Each uploader's EventManager       │
│    receives the event                 │
└───────────────────────────────────────┘
                │
                ▼
┌───────────────────────────────────────┐
│ 4. Uploader-specific pause logic      │
│    - Tus: upload.abort()              │
│    - S3: AbortController.abort()      │
│    - XHR: Not supported (no-op)       │
└───────────────────────────────────────┘
```

---

## Core API Methods

### `pauseResume(fileID: string): boolean | undefined`

Toggle pause/resume for a single file.

```typescript
pauseResume(fileID: string): boolean | undefined {
  // Check if resumable uploads are supported
  if (
    !this.getState().capabilities.resumableUploads ||
    this.getFile(fileID).progress.uploadComplete
  ) {
    return undefined;  // Can't pause/resume
  }

  const file = this.getFile(fileID);
  const wasPaused = file.isPaused || false;
  const isPaused = !wasPaused;

  // Update file state
  this.setFileState(fileID, { isPaused });

  // Emit event for uploaders to handle
  this.emit('upload-pause', file, isPaused);

  return isPaused;
}
```

**Key Points**:
- Returns `undefined` if resumable uploads not supported
- Returns `undefined` if file already completed
- Returns new `isPaused` state (true/false)
- Emits `upload-pause` event with the paused state

### `pauseAll(): void`

Pause all in-progress uploads.

```typescript
pauseAll(): void {
  const updatedFiles = { ...this.getState().files };

  // Find all in-progress files (started but not complete)
  const inProgressUpdatedFiles = Object.keys(updatedFiles).filter((file) => {
    return (
      !updatedFiles[file].progress.uploadComplete &&
      updatedFiles[file].progress.uploadStarted
    );
  });

  // Set isPaused = true for all
  inProgressUpdatedFiles.forEach((file) => {
    const updatedFile = { ...updatedFiles[file], isPaused: true };
    updatedFiles[file] = updatedFile;
  });

  this.setState({ files: updatedFiles });
  this.emit('pause-all');  // Uploaders listen to this
}
```

**Key Points**:
- Only affects files that have started but not completed
- Sets `isPaused: true` for all matching files
- Emits single `pause-all` event (not per-file events)

### `resumeAll(): void`

Resume all paused uploads.

```typescript
resumeAll(): void {
  const updatedFiles = { ...this.getState().files };

  // Find all in-progress files
  const inProgressUpdatedFiles = Object.keys(updatedFiles).filter((file) => {
    return (
      !updatedFiles[file].progress.uploadComplete &&
      updatedFiles[file].progress.uploadStarted
    );
  });

  // Clear isPaused and error for all
  inProgressUpdatedFiles.forEach((file) => {
    const updatedFile = {
      ...updatedFiles[file],
      isPaused: false,
      error: null,  // Clear any errors
    };
    updatedFiles[file] = updatedFile;
  });

  this.setState({ files: updatedFiles });
  this.emit('resume-all');  // Uploaders listen to this
}
```

**Key Points**:
- Clears `isPaused` AND `error` state
- This means resumeAll can also retry errored files
- Emits single `resume-all` event

### `cancelAll(): void`

Cancel all uploads and remove all files.

```typescript
cancelAll(): void {
  // Emit FIRST so uploaders can cleanup
  this.emit('cancel-all');

  const { files } = this.getState();
  const fileIDs = Object.keys(files);

  if (fileIDs.length) {
    this.removeFiles(fileIDs);  // This triggers cleanup
  }

  // Reset to default upload state
  this.setState({
    totalProgress: 0,
    allowNewUpload: true,
    error: null,
    recoveredState: null,
  });
}
```

**Key Points**:
- Emits `cancel-all` BEFORE removing files (so uploaders can abort)
- Removes ALL files from state
- Resets upload state to defaults
- Uploaders should abort any in-progress HTTP requests

### `retryUpload(fileID: string): Promise<UploadResult | undefined>`

Retry a single failed file.

```typescript
retryUpload(fileID: string): Promise<UploadResult | undefined> {
  // Clear error state
  this.setFileState(fileID, {
    error: null,
    isPaused: false,
  });

  this.emit('upload-retry', this.getFile(fileID));

  // Create new upload for just this file
  const uploadID = this.#createUpload([fileID], {
    forceAllowNewUpload: true,  // Bypass allowNewUpload check
  });

  return this.#runUpload(uploadID);
}
```

### `retryAll(): Promise<UploadResult | undefined>`

Retry all failed files.

```typescript
async retryAll(): Promise<UploadResult | undefined> {
  // Find files with errors (and no missing metadata)
  const filesToRetry = this.#getFilesToRetry();

  // Clear error state for all
  const updatedFiles = { ...this.getState().files };
  filesToRetry.forEach((fileID) => {
    updatedFiles[fileID] = {
      ...updatedFiles[fileID],
      isPaused: false,
      error: null,
    };
  });

  this.setState({ files: updatedFiles, error: null });
  this.emit('retry-all', this.getFilesByIds(filesToRetry));

  if (filesToRetry.length === 0) {
    return { successful: [], failed: [] };
  }

  const uploadID = this.#createUpload(filesToRetry, {
    forceAllowNewUpload: true,
  });

  const result = await this.#runUpload(uploadID);
  this.emit('complete', result);
  return result;
}
```

---

## EventManager - Event Coordination

The `EventManager` class provides per-file event filtering and lifecycle management.

### Purpose

1. **Per-File Event Filtering**: Converts global events to file-specific callbacks
2. **Cleanup Management**: Tracks all listeners and removes them on upload complete/cancel
3. **Reduces Boilerplate**: Uploaders don't need to filter events manually

### Key Methods

```typescript
class EventManager<M extends Meta, B extends Body> {
  #uppy: Uppy<M, B>;
  #events: Array<[eventName, handler]> = [];

  constructor(uppy: Uppy<M, B>) {
    this.#uppy = uppy;
  }

  // Add listener and track for later cleanup
  on<K extends keyof UppyEventMap>(event: K, fn: UppyEventMap[K]): Uppy {
    this.#events.push([event, fn]);
    return this.#uppy.on(event, fn);
  }

  // Remove ALL tracked listeners
  remove(): void {
    for (const [event, fn] of this.#events.splice(0)) {
      this.#uppy.off(event, fn);
    }
  }

  // Per-file event handlers
  onPause(fileID: string, cb: (isPaused: boolean) => void): void {
    this.on('upload-pause', (file, isPaused) => {
      if (fileID === file?.id) {
        cb(isPaused);
      }
    });
  }

  onPauseAll(fileID: string, cb: () => void): void {
    this.on('pause-all', () => {
      if (!this.#uppy.getFile(fileID)) return;  // File might be removed
      cb();
    });
  }

  onResumeAll(fileID: string, cb: () => void): void {
    this.on('resume-all', () => {
      if (!this.#uppy.getFile(fileID)) return;
      cb();
    });
  }

  onCancelAll(fileID: string, cb: () => void): void {
    this.on('cancel-all', (...args) => {
      if (!this.#uppy.getFile(fileID)) return;
      cb(...args);
    });
  }

  onFileRemove(fileID: string, cb: (fileID: string) => void): void {
    this.on('file-removed', (file) => {
      if (fileID === file.id) cb(file.id);
    });
  }

  onRetry(fileID: string, cb: () => void): void {
    this.on('upload-retry', (file) => {
      if (fileID === file?.id) {
        cb();
      }
    });
  }

  onRetryAll(fileID: string, cb: () => void): void {
    this.on('retry-all', () => {
      if (!this.#uppy.getFile(fileID)) return;
      cb();
    });
  }
}
```

### Usage Pattern in Uploaders

```typescript
// In upload function
const eventManager = new EventManager(this.uppy);
this.uploaderEvents[file.id] = eventManager;

// Register pause handler
eventManager.onPause(file.id, (isPaused) => {
  if (isPaused) {
    upload.abort();
  } else {
    queuedRequest = this.requests.run(qRequest);  // Resume
  }
});

eventManager.onPauseAll(file.id, () => {
  queuedRequest.abort();
  upload.abort();
});

eventManager.onCancelAll(file.id, () => {
  queuedRequest.abort();
  this.resetUploaderReferences(file.id, { abort: true });
  resolve(`upload ${file.id} was canceled`);
});

eventManager.onResumeAll(file.id, () => {
  queuedRequest.abort();  // Remove from queue first
  queuedRequest = this.requests.run(qRequest);  // Re-queue
});

// Cleanup when upload completes or is cancelled
this.resetUploaderReferences(file.id);  // Calls eventManager.remove()
```

---

## RateLimitedQueue - Concurrent Upload Management

The `RateLimitedQueue` manages concurrent uploads with pause/resume support.

### Key Features

1. **Concurrency Limiting**: Maximum `N` concurrent uploads
2. **Queue Management**: Pending uploads wait in a priority queue
3. **Pause/Resume**: Can pause entire queue or individual requests
4. **Rate Limiting**: Handles HTTP 429 responses with exponential backoff

### Core Interface

```typescript
interface Handler {
  fn: () => () => void;     // The upload function, returns cancel function
  priority: number;
  abort: (cause?: unknown) => void;
  done: () => void;
  shouldBeRequeued?: boolean;  // For rate-limiting scenarios
}

class RateLimitedQueue {
  #activeRequests = 0;
  #queuedHandlers: Handler[] = [];
  #paused = false;
  limit: number;

  // Run immediately if under limit, else queue
  run(fn: Handler['fn'], options?: QueueOptions): Handler;

  // Pause the queue (optionally for a duration)
  pause(duration?: number): void;

  // Resume the queue
  resume(): void;

  // Rate limit (pause + reduce concurrency)
  rateLimit(duration: number): void;

  get isPaused(): boolean;
}
```

### How Pause Works with Queue

```typescript
// When pause-all is emitted:
eventManager.onPauseAll(file.id, () => {
  queuedRequest.abort();  // Remove from queue / cancel active
  upload.abort();         // Stop the actual upload
});

// What queuedRequest.abort() does:
abort: (cause?: unknown) => {
  if (done) return;
  done = true;
  this.#activeRequests -= 1;  // Decrement active count
  cancelActive?.(cause);       // Call the cancel function
  this.#queueNext();           // Start next queued upload
}
```

### Resume Flow

```typescript
// When resume-all is emitted:
eventManager.onResumeAll(file.id, () => {
  queuedRequest.abort();  // Clear previous queue entry
  // Re-queue the upload (goes through limit check)
  queuedRequest = this.requests.run(qRequest);
});
```

**Important**: Resume doesn't just "unpause" - it re-queues the upload. This ensures:
1. The concurrent limit is respected
2. Other uploads can't be "starved" by selective pausing

---

## Tus Uploader Implementation

Tus uses the `tus-js-client` library which has native pause/resume support.

### Key Components

```typescript
class Tus extends BasePlugin {
  requests: RateLimitedQueue;           // Concurrent upload management
  uploaders: Record<string, tus.Upload | null>;     // Active tus uploads
  uploaderEvents: Record<string, EventManager | null>; // Event handlers
}
```

### Pause/Resume Logic

```typescript
async #uploadLocalFile(file: LocalUppyFile) {
  // Create tus.Upload instance
  const upload = new tus.Upload(file.data, uploadOptions);
  this.uploaders[file.id] = upload;

  const eventManager = new EventManager(this.uppy);
  this.uploaderEvents[file.id] = eventManager;

  // The upload function (called by queue)
  const qRequest = () => {
    if (!file.isPaused) {
      upload.start();  // Start or resume tus upload
    }
    return () => {};   // No cleanup needed (handled elsewhere)
  };

  // Queue the upload
  let queuedRequest = this.requests.run(qRequest);

  // PAUSE: Single file
  eventManager.onPause(file.id, (isPaused) => {
    queuedRequest.abort();  // Remove from queue
    if (isPaused) {
      upload.abort();       // Abort tus upload (preserves state)
    } else {
      // Re-queue to respect concurrency limit
      queuedRequest = this.requests.run(qRequest);
    }
  });

  // PAUSE ALL
  eventManager.onPauseAll(file.id, () => {
    queuedRequest.abort();
    upload.abort();
  });

  // RESUME ALL
  eventManager.onResumeAll(file.id, () => {
    queuedRequest.abort();  // Clear old queue entry
    if (file.error) {
      upload.abort();       // Abort errored upload
    }
    queuedRequest = this.requests.run(qRequest);  // Re-queue
  });

  // CANCEL ALL
  eventManager.onCancelAll(file.id, () => {
    queuedRequest.abort();
    this.resetUploaderReferences(file.id, { abort: !!upload.url });
    resolve(`upload ${file.id} was canceled`);
  });

  // FILE REMOVED
  eventManager.onFileRemove(file.id, (targetFileID) => {
    queuedRequest.abort();
    this.resetUploaderReferences(file.id, { abort: !!upload.url });
    resolve(`upload ${targetFileID} was removed`);
  });
}
```

### Cleanup

```typescript
resetUploaderReferences(fileID: string, opts?: { abort: boolean }): void {
  const uploader = this.uploaders[fileID];
  if (uploader) {
    uploader.abort();  // Stop the tus upload

    if (opts?.abort) {
      uploader.abort(true);  // Delete from server too
    }

    this.uploaders[fileID] = null;
  }

  if (this.uploaderEvents[fileID]) {
    this.uploaderEvents[fileID].remove();  // Remove all event listeners
    this.uploaderEvents[fileID] = null;
  }
}
```

### Tus Resume Mechanism

Tus protocol supports true resumability:

```typescript
// Tus stores upload state with fingerprint
uploadOptions.fingerprint = getFingerprint(file);  // Based on file.id

// On start, tus-js-client checks for existing uploads
upload.findPreviousUploads().then((previousUploads) => {
  const previousUpload = previousUploads[0];
  if (previousUpload) {
    upload.resumeFromPreviousUpload(previousUpload);
  }
  queuedRequest = this.requests.run(qRequest);
});
```

### Capability Declaration

```typescript
install(): void {
  this.uppy.setState({
    capabilities: {
      ...this.uppy.getState().capabilities,
      resumableUploads: true,  // Enable pause/resume UI
    },
  });
  this.uppy.addUploader(this.#handleUpload);
}

uninstall(): void {
  this.uppy.setState({
    capabilities: {
      ...this.uppy.getState().capabilities,
      resumableUploads: false,
    },
  });
  this.uppy.removeUploader(this.#handleUpload);
}
```

---

## AWS S3 Uploader Implementation

S3 uploader uses `AbortController` and a custom `MultipartUploader` class.

### Key Components

```typescript
class AwsS3Multipart extends BasePlugin {
  requests: RateLimitedQueue;
  uploaders: Record<string, MultipartUploader | null>;
  uploaderEvents: Record<string, EventManager | null>;
}
```

### MultipartUploader - Pause/Resume

The `MultipartUploader` class handles the actual pause/resume logic:

```typescript
class MultipartUploader {
  #abortController = new AbortController();

  // Custom Symbol for pausing (not a real error)
  static pausingUploadReason = Symbol('pausing upload, not an actual error');

  pause(): void {
    // Abort with special "pausing" reason
    this.#abortController.abort(pausingUploadReason);
    // Create new controller for when we resume
    this.#abortController = new AbortController();
  }

  start(): void {
    if (this.#uploadHasStarted) {
      // If paused, abort pending and restart
      if (!this.#abortController.signal.aborted) {
        this.#abortController.abort(pausingUploadReason);
      }
      this.#abortController = new AbortController();
      this.#resumeUpload();  // Resume from where we left off
    } else if (this.#isRestoring) {
      // Restoring from saved state
      this.#resumeUpload();
    } else {
      // First start
      this.#createUpload();
    }
  }

  abort(opts?: { really?: boolean }): void {
    if (opts?.really) {
      this.#abortUpload();  // Actually abort on server
    } else {
      this.pause();  // Just pause
    }
  }

  // Error handler ignores pause "errors"
  #onReject = (err: unknown) =>
    (err as any)?.cause === pausingUploadReason
      ? null  // Ignore pause errors
      : this.#onError(err);
}
```

### S3 Plugin Event Handling

```typescript
#uploadLocalFile(file: LocalUppyFile) {
  return new Promise((resolve, reject) => {
    const upload = new MultipartUploader(file.data, {
      // ... options
    });

    this.uploaders[file.id] = upload;
    const eventManager = new EventManager(this.uppy);
    this.uploaderEvents[file.id] = eventManager;

    // PAUSE: Single file
    eventManager.onFilePause(file.id, (isPaused) => {
      if (isPaused) {
        upload.pause();
      } else {
        upload.start();
      }
    });

    // PAUSE ALL
    eventManager.onPauseAll(file.id, () => {
      upload.pause();
    });

    // RESUME ALL
    eventManager.onResumeAll(file.id, () => {
      upload.start();
    });

    // CANCEL ALL
    eventManager.onCancelAll(file.id, () => {
      upload.abort();  // Pause only
      this.resetUploaderReferences(file.id, { abort: true });  // Cleanup + abort on server
      resolve(`upload ${file.id} was canceled`);
    });

    // FILE REMOVED
    eventManager.onFileRemove(file.id, (removed) => {
      upload.abort();
      this.resetUploaderReferences(file.id, { abort: true });
      resolve(`upload ${removed} was removed`);
    });

    // Start the upload
    upload.start();
  });
}
```

### S3 Multipart Resume Mechanism

S3 multipart uploads can be resumed by listing already-uploaded parts:

```typescript
// State is stored on the file object
this.uppy.setFileState(file.id, {
  s3Multipart: {
    key: string,      // S3 object key
    uploadId: string, // Multipart upload ID
  },
});

// On resume, list uploaded parts and skip them
#resumeUpload() {
  this.options.companionComm
    .resumeUploadFile(this.#file, this.#chunks, this.#abortController.signal)
    .then(this.#onSuccess, this.#onReject);
}
```

### Capability Declaration

```typescript
install(): void {
  this.#setResumableUploadsCapability(true);
  this.uppy.addUploader(this.#upload);
}

#setResumableUploadsCapability(boolean: boolean) {
  const { capabilities } = this.uppy.getState();
  this.uppy.setState({
    capabilities: {
      ...capabilities,
      resumableUploads: boolean,
    },
  });
}
```

**Note**: S3 sets `resumableUploads: false` during remote uploads:

```typescript
if (file.isRemote) {
  this.#setResumableUploadsCapability(false);  // Can't pause remote
  // ... upload
  // After upload completes:
  this.#setResumableUploadsCapability(true);
}
```

---

## XHR Uploader Implementation

XHR upload does **NOT** support pause/resume (non-resumable protocol).

### Key Characteristics

1. **No `resumableUploads` capability**: Doesn't declare the capability
2. **Cancel-only**: Uses `AbortController` for cancellation only
3. **Bundle mode**: Can disable individual cancellation too

### Implementation

```typescript
class XHRUpload extends BasePlugin {
  requests: RateLimitedQueue;
  uploaderEvents: Record<string, EventManager | null>;

  async #uploadLocalFile(file: LocalUppyFile) {
    const events = new EventManager(this.uppy);
    const controller = new AbortController();

    // Wrap upload in queue
    const uppyFetch = this.requests.wrapPromiseFunction(async () => {
      const fetch = this.#getFetcher([file]);
      return fetch(endpoint, {
        ...opts,
        body,
        signal: controller.signal,  // For cancellation
      });
    });

    // CANCEL: File removed
    events.onFileRemove(file.id, () => controller.abort());

    // CANCEL ALL
    events.onCancelAll(file.id, () => {
      controller.abort();
    });

    // NOTE: No onPause, onPauseAll, onResumeAll handlers!

    try {
      await uppyFetch();
    } catch (error) {
      if (error.message !== 'Cancelled') {
        throw error;
      }
    } finally {
      events.remove();
    }
  }
}
```

### Bundle Mode - Disables Individual Cancellation

```typescript
install(): void {
  if (this.opts.bundle) {
    // Can't cancel individual files when bundling
    const { capabilities } = this.uppy.getState();
    this.uppy.setState({
      capabilities: {
        ...capabilities,
        individualCancellation: false,  // Disable
      },
    });
  }

  this.uppy.addUploader(this.#handleUpload);
}

// Bundle upload only listens to cancel-all, not per-file events
async #uploadBundle(files: LocalUppyFile[]) {
  const controller = new AbortController();

  function abort() {
    controller.abort();
  }

  this.uppy.once('cancel-all', abort);  // Only cancel-all

  try {
    await uppyFetch();
  } finally {
    this.uppy.off('cancel-all', abort);
  }
}
```

---

## Key Design Patterns

### 1. Two-Phase Event Handling

Core emits events, uploaders handle protocol-specific logic:

```
Core                          Uploader
─────                         ────────
pauseAll() {                  eventManager.onPauseAll(() => {
  updateState()                 queuedRequest.abort()
  emit('pause-all')  ──────►    upload.abort()
}                             })
```

### 2. Queue-Based Concurrency

All uploaders use `RateLimitedQueue`:

```typescript
// Start: Add to queue
queuedRequest = this.requests.run(uploadFn);

// Pause: Remove from queue
queuedRequest.abort();
upload.abort();

// Resume: Re-add to queue (respects limit)
queuedRequest = this.requests.run(uploadFn);
```

### 3. Cleanup Pattern

Every uploader follows this cleanup pattern:

```typescript
resetUploaderReferences(fileID: string, opts?: { abort: boolean }): void {
  // 1. Abort the protocol-specific upload
  const uploader = this.uploaders[fileID];
  if (uploader) {
    uploader.abort();
    if (opts?.abort) {
      uploader.abort(true);  // Server-side abort if needed
    }
    this.uploaders[fileID] = null;
  }

  // 2. Remove all event listeners
  if (this.uploaderEvents[fileID]) {
    this.uploaderEvents[fileID].remove();
    this.uploaderEvents[fileID] = null;
  }
}
```

### 4. Capability-Based UI

UI checks capabilities before showing pause/resume buttons:

```typescript
const { capabilities } = uppy.getState();
if (capabilities.resumableUploads) {
  // Show pause button
}
if (capabilities.individualCancellation) {
  // Show per-file cancel button
}
```

### 5. Error vs Pause Distinction

Uploaders distinguish between errors and intentional pauses:

```typescript
// S3: Uses Symbol
const pausingUploadReason = Symbol('pausing upload');
this.#abortController.abort(pausingUploadReason);

// Error handler ignores pause "errors"
#onReject = (err) =>
  err?.cause === pausingUploadReason ? null : this.#onError(err);
```

```typescript
// Tus: Uses flag checking
if (file.error) {
  upload.abort();  // Abort errored upload
}
queuedRequest = this.requests.run(qRequest);  // Re-queue
```

---

## Comparison Summary

| Feature | Tus | AWS S3 | XHR |
|---------|-----|--------|-----|
| **Resumable Uploads** | Yes | Yes | No |
| **Individual File Pause** | Yes | Yes | No |
| **Pause All** | Yes | Yes | No |
| **Resume All** | Yes | Yes | No |
| **Cancel All** | Yes | Yes | Yes |
| **Individual Cancel** | Yes | Yes | Yes (unless bundle) |
| **Resume Mechanism** | tus protocol (fingerprint) | S3 multipart (uploadId, parts list) | N/A |
| **Uses Queue** | Yes | Yes | Yes |
| **Uses AbortController** | No (tus library handles) | Yes | Yes |
| **Server-side Abort** | Yes (delete upload URL) | Yes (abort multipart) | N/A |

---

## Fluppy Implementation Recommendations

Based on this analysis, here are recommendations for Fluppy:

### 1. Core State Structure

```dart
class FluppyFile {
  bool isPaused = false;
  String? error;
  FileProgress progress;

  // Uploader-specific state for resume
  Map<String, dynamic>? uploaderState;  // e.g., {'uploadId': '...', 'key': '...'}
}

class FluppyCapabilities {
  bool uploadProgress = true;
  bool individualCancellation = true;
  bool resumableUploads = false;  // Set by uploader plugin
}
```

### 2. Core API Methods

```dart
class Fluppy {
  // Single file pause/resume toggle
  bool? pauseResume(String fileId);

  // Batch operations
  void pauseAll();
  void resumeAll();
  void cancelAll();

  // Retry operations
  Future<UploadResult?> retryUpload(String fileId);
  Future<UploadResult?> retryAll();
}
```

### 3. Event System

Use Dart sealed classes:

```dart
sealed class FluppyEvent {}

class UploadPaused extends FluppyEvent {
  final String fileId;
  final bool isPaused;
}

class PauseAll extends FluppyEvent {}
class ResumeAll extends FluppyEvent {}
class CancelAll extends FluppyEvent {}
class UploadRetry extends FluppyEvent {
  final FluppyFile file;
}
class RetryAll extends FluppyEvent {
  final List<FluppyFile> files;
}
```

### 4. EventManager Equivalent

```dart
class UploaderEventManager {
  final Fluppy _fluppy;
  final List<StreamSubscription> _subscriptions = [];

  void onPause(String fileId, void Function(bool isPaused) callback) {
    _subscriptions.add(_fluppy.events.listen((event) {
      if (event is UploadPaused && event.fileId == fileId) {
        callback(event.isPaused);
      }
    }));
  }

  void onPauseAll(String fileId, void Function() callback) {
    _subscriptions.add(_fluppy.events.listen((event) {
      if (event is PauseAll && _fluppy.getFile(fileId) != null) {
        callback();
      }
    }));
  }

  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}
```

### 5. Queue with Pause Support

```dart
class RateLimitedQueue {
  final int limit;
  final Queue<_QueuedRequest> _queue = Queue();
  int _activeRequests = 0;
  bool _paused = false;

  Future<T> run<T>(Future<T> Function() fn);
  void pause();
  void resume();
  bool get isPaused;
}
```

### 6. Uploader Base Pattern

```dart
abstract class Uploader {
  final Map<String, CancellationToken> _uploaders = {};
  final Map<String, UploaderEventManager> _events = {};

  void resetUploaderReferences(String fileId, {bool abort = false}) {
    final token = _uploaders[fileId];
    if (token != null) {
      token.cancel();
      if (abort) {
        // Protocol-specific server-side abort
        abortOnServer(fileId);
      }
      _uploaders.remove(fileId);
    }

    _events[fileId]?.dispose();
    _events.remove(fileId);
  }

  // Override in subclasses
  Future<void> abortOnServer(String fileId);
}
```

### 7. S3 Uploader Pattern

```dart
class S3Uploader extends Uploader {
  @override
  Future<void> uploadFile(FluppyFile file, CancellationToken token) async {
    final eventManager = UploaderEventManager(_fluppy);
    _events[file.id] = eventManager;

    eventManager.onPause(file.id, (isPaused) {
      if (isPaused) {
        _pause(file.id);
      } else {
        _resume(file.id);
      }
    });

    eventManager.onPauseAll(file.id, () => _pause(file.id));
    eventManager.onResumeAll(file.id, () => _resume(file.id));
    eventManager.onCancelAll(file.id, () {
      resetUploaderReferences(file.id, abort: true);
    });

    // ... upload logic
  }

  void _pause(String fileId) {
    _abortControllers[fileId]?.cancel();
    _abortControllers[fileId] = CancellationToken();
  }

  void _resume(String fileId) {
    // Re-queue the upload
  }
}
```

---

## Conclusion

Uppy's pause/resume/cancel implementation is well-architected with clear separation of concerns:

1. **Core** handles state and event emission
2. **EventManager** provides per-file event filtering
3. **RateLimitedQueue** manages concurrency
4. **Uploaders** implement protocol-specific logic

The key insight is that **pause is not just "stopping"** - it involves:
- Updating file state (`isPaused: true`)
- Removing from the upload queue
- Aborting in-progress HTTP requests
- Preserving state for resume (upload URLs, part lists, etc.)

**Resume** then involves:
- Clearing pause/error state
- Re-queuing the upload (respecting concurrency limits)
- Resuming from saved state (if supported by protocol)

This architecture should be replicated in Fluppy for 1:1 feature parity.
