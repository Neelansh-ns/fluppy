# Uppy Comprehensive Study & Reference Guide

> **Purpose**: This document serves as the comprehensive reference for building fluppy, a Flutter package that aims to be 1:1 similar to Uppy.js. All architectural decisions, API designs, and feature implementations should align with the patterns documented here.

**Last Updated**: 2026-01-11
**Uppy Version Referenced**: Latest (as of Jan 2026)
**Official Documentation**: https://uppy.io/docs/

---

## Table of Contents

1. [Overview & Philosophy](#overview--philosophy)
2. [Core Architecture](#core-architecture)
3. [State Management](#state-management)
4. [File Object Model](#file-object-model)
5. [Event System](#event-system)
6. [Upload Lifecycle & Pipeline](#upload-lifecycle--pipeline)
7. [Plugin System](#plugin-system)
8. [Uploader Implementations](#uploader-implementations)
9. [Configuration & Options](#configuration--options)
10. [API Reference](#api-reference)
11. [Fluppy Mapping Strategy](#fluppy-mapping-strategy)

---

## Overview & Philosophy

### What is Uppy?

Uppy is a **sleek, modular JavaScript file uploader** that integrates seamlessly with any application. It's:
- **Fast**: Optimized for performance
- **Modular**: Plugin-based architecture
- **Lightweight**: Light on dependencies
- **Headless**: No UI required (but UI plugins available)
- **Resumable**: Built-in support for resumable uploads via tus protocol
- **Flexible**: Supports local files, remote sources (Google Drive, Dropbox, etc.)

### Core Design Principles

1. **Modularity First**: Core orchestrator + plugin ecosystem
2. **Backend-Agnostic**: Works with any upload backend
3. **User-Centric**: Comprehensive progress tracking and error handling
4. **Resumability**: Network interruptions shouldn't restart uploads
5. **Extensibility**: Easy to add custom functionality via plugins
6. **Separation of Concerns**: State management, UI, and upload logic are separate

---

## Core Architecture

### The Orchestrator Pattern

Uppy Core (`@uppy/core`) functions as:
- **State Manager**: Immutable state store with Redux-like patterns
- **Event Emitter**: Pub/sub system for lifecycle events
- **Restrictions Handler**: File validation and constraints enforcement
- **Plugin Manager**: Install/uninstall/lifecycle management
- **Upload Coordinator**: Controls upload pipeline execution

```
┌─────────────────────────────────────────────┐
│           Uppy Core (Orchestrator)          │
│  ┌────────────┐  ┌──────────┐  ┌─────────┐ │
│  │   State    │  │  Events  │  │ Plugins │ │
│  │  Manager   │  │ Emitter  │  │ Manager │ │
│  └────────────┘  └──────────┘  └─────────┘ │
└─────────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
  ┌─────▼──────┐         ┌─────▼──────┐
  │ UI Plugins │         │  Uploader  │
  │ (Optional) │         │  Plugins   │
  └────────────┘         └────────────┘
```

### Plugin-Based Architecture

Features are added incrementally through plugins:

**Plugin Categories:**
1. **UI Plugins**: Dashboard, Drag & Drop, File Input, Webcam
2. **Upload Plugins**: Tus, XHR Upload, AWS S3, Transloadit
3. **Processing Plugins**: Image Editor, Thumbnail Generator, Golden Retriever (state recovery)
4. **Remote Source Plugins**: Google Drive, Dropbox, Instagram, Box

**Key Insight**: Uppy Core can function **without any UI plugins**—developers can build completely custom interfaces.

---

## State Management

### State Structure

Uppy maintains an **immutable state object**:

```javascript
{
  plugins: {},              // Plugin registry
  files: {},                // File objects keyed by ID
  currentUploads: {},       // Active upload tracking
  capabilities: {           // Feature detection
    resumableUploads: false
  },
  totalProgress: 0,         // 0-100 aggregate progress
  meta: {},                 // Global metadata
  info: {                   // Notification state
    isHidden: true,
    type: 'info',
    message: ''
  }
}
```

### State Mutation Rules

**Immutability Pattern** (Redux-style):
- State mutations create **copies**, never modify directly
- Use spread operators or Object.assign
- Enables time-travel debugging and predictable behavior

**State Access Methods:**
- `getState()`: Retrieve current state snapshot
- `setState(patch)`: Merge patch into state (shallow merge)
- `setFileState(fileID, state)`: Update individual file state

### Custom State Management

Uppy supports **custom stores** (e.g., Redux integration):
- Provide store with `getState()` and `setState()` methods
- Uppy will use your store instead of internal one
- Enables unified state management across app

---

## File Object Model

### Core Properties

Every file in Uppy is a wrapped object:

```javascript
{
  id: 'uppy-generated-unique-id',
  name: 'vacation.jpg',
  extension: 'jpg',
  type: 'image/jpeg',
  size: 2097152,              // bytes
  data: File,                 // Browser File/Blob (local only)
  source: 'Dashboard',        // Plugin name that added this file
  isRemote: false,            // Remote provider file?

  meta: {                     // Extensible metadata
    name: 'vacation.jpg',
    type: 'image/jpeg',
    relativePath: 'photos/vacation.jpg',
    absolutePath: '/Drive/photos/vacation.jpg'
  },

  progress: {                 // Upload tracking
    bytesUploaded: 0,
    bytesTotal: 2097152,
    uploadStarted: 1640000000000,
    uploadComplete: false,
    percentage: 0
  },

  preview: 'data:image/jpeg;base64,...',  // Optional thumbnail
  uploadURL: 'https://cdn.com/file.jpg',  // Post-upload URL
  remote: {},                             // Provider metadata

  response: {                 // Server response
    status: 200,
    body: {},
    uploadURL: 'https://...'
  }
}
```

### File Source Types

Uppy supports multiple file sources:

1. **Local Files**: Standard browser File objects
2. **Remote Files**: From Google Drive, Dropbox, etc.
3. **Webcam**: Live capture
4. **URL Import**: Fetch from external URLs
5. **Clipboard**: Paste from clipboard

**Important**: `file.data` only exists for local files. Remote files use `file.remote` metadata.

### Path Tracking

**Local Files:**
- `relativePath`: Path relative to dropped folder (e.g., "folder1/folder2/file.jpg")

**Remote Files:**
- `absolutePath`: Full path from provider root
- Reflects user's navigation depth in provider

---

## Event System

### Event-Driven Architecture

Uppy emits **granular events** for every lifecycle stage:

```javascript
uppy.on('event-name', (data) => {
  // Handle event
})
```

### Event Catalog

#### File Management Events

| Event | When Fired | Payload |
|-------|------------|---------|
| `file-added` | Single file added | `(file)` |
| `files-added` | Multiple files added | `(files[])` |
| `file-removed` | File deleted | `(file, reason)` |

#### Upload Lifecycle Events

| Event | When Fired | Payload |
|-------|------------|---------|
| `upload` | Upload initiated | `(data: { id, fileIDs })` |
| `upload-start` | Single file starts | `(file)` |
| `upload-progress` | Progress update | `(file, progress)` |
| `upload-success` | File completed | `(file, response)` |
| `upload-error` | Upload failed | `(file, error, response)` |
| `upload-retry` | Retry initiated | `(fileID)` |
| `retry-all` | All retried | `(fileIDs)` |
| `upload-pause` | Upload paused | `(fileID, isPaused)` |
| `upload-stalled` | No progress timeout | `()` |
| `complete` | All finished | `(result)` |
| `cancel-all` | All cancelled | `()` |

#### Processing Events

| Event | When Fired | Payload |
|-------|------------|---------|
| `preprocess-progress` | Pre-processing | `(file, progress)` |
| `postprocess-progress` | Post-processing | `(file, progress)` |
| `preprocess-complete` | Batch pre-processed | `(fileID)` |
| `postprocess-complete` | Batch post-processed | `(fileID)` |

#### Progress Events

| Event | When Fired | Payload |
|-------|------------|---------|
| `progress` | Total progress update | `(progress: 0-100)` |

#### Notification Events

| Event | When Fired | Payload |
|-------|------------|---------|
| `info-visible` | Info message shown | `()` |
| `info-hidden` | Info message hidden | `()` |
| `restriction-failed` | Validation failed | `(file, error)` |

#### System Events

| Event | When Fired | Payload |
|-------|------------|---------|
| `error` | Critical error | `(error)` |
| `reset` | State cleared | `()` |

### Progress Event Modes

**Determinate Progress** (with known total):
```javascript
uppy.emit('preprocess-progress', file, {
  mode: 'determinate',
  message: 'Processing...',
  value: 50  // 0-100
})
```

**Indeterminate Progress** (unknown duration):
```javascript
uppy.emit('preprocess-progress', file, {
  mode: 'indeterminate',
  message: 'Analyzing...'
})
```

---

## Upload Lifecycle & Pipeline

### Three-Phase Pipeline

Uppy processes files through **three distinct phases**:

```
┌──────────────┐    ┌──────────┐    ┌───────────────┐
│ Preprocessing│ -> │ Uploading│ -> │ Postprocessing│
└──────────────┘    └──────────┘    └───────────────┘
```

#### 1. Preprocessing Phase

**Purpose**: Prepare files before upload
**Use Cases**:
- Image resizing/compression
- File encryption
- Metadata extraction
- Format conversion
- Validation

**API**:
```javascript
uppy.addPreProcessor((fileIDs) => {
  return new Promise((resolve, reject) => {
    // Process files
    // Use uppy.setFileState() to modify files
    resolve()
  })
})
```

#### 2. Uploading Phase

**Purpose**: Transmit files to destination
**Use Cases**:
- HTTP upload
- Resumable upload (tus)
- Cloud storage (S3, GCS)
- Custom protocols

**API**:
```javascript
uppy.addUploader((fileIDs) => {
  return new Promise((resolve, reject) => {
    // Upload files
    // Emit upload-progress events
    resolve()
  })
})
```

#### 3. Postprocessing Phase

**Purpose**: Actions after successful upload
**Use Cases**:
- CDN propagation waiting
- Thumbnail generation (server-side)
- Database record creation
- Webhook notifications
- Encoding completion

**API**:
```javascript
uppy.addPostProcessor((fileIDs) => {
  return new Promise((resolve, reject) => {
    // Post-process
    resolve()
  })
})
```

### Processor Management

**Removal**:
```javascript
const fn = (fileIDs) => { /* ... */ }
uppy.addPreProcessor(fn)
uppy.removePreProcessor(fn)  // Must be same function reference
```

**Critical**: Bind functions before adding to enable removal:
```javascript
this.myProcessor = this.myProcessor.bind(this)
uppy.addPreProcessor(this.myProcessor)
```

---

## Plugin System

### Plugin Base Classes

#### BasePlugin (Non-UI)

For plugins without user interface:

```javascript
class MyPlugin extends BasePlugin {
  constructor(uppy, opts) {
    super(uppy, opts)
    this.id = opts.id || 'MyPlugin'
    this.type = 'uploader'  // or 'acquirer', 'modifier', etc.
  }

  install() {
    // Setup: attach event listeners
  }

  uninstall() {
    // Cleanup: remove listeners, cancel operations
  }

  afterUpdate() {
    // Called after state changes (debounced)
  }
}
```

#### UIPlugin (With UI)

For plugins that render interface:

```javascript
class MyUIPlugin extends UIPlugin {
  constructor(uppy, opts) {
    super(uppy, opts)
    this.id = opts.id || 'MyUIPlugin'
    this.type = 'acquirer'
  }

  render() {
    // Return Preact elements
    return <div>My Plugin UI</div>
  }

  mount(target, plugin) {
    // Attach to DOM or parent plugin
  }

  onMount() {
    // After render completes
  }

  onUnmount() {
    // Before removal
  }
}
```

### Plugin Lifecycle

1. **Registration**: `uppy.use(MyPlugin, options)`
2. **Installation**: `install()` method called
3. **Mounting** (UI plugins): `mount()` called
4. **Rendering** (UI plugins): `render()` called on state changes
5. **Updates**: `afterUpdate()` called after state mutations
6. **Uninstallation**: `uninstall()` method called
7. **Removal**: `uppy.removePlugin(instance)`

### Plugin Types

Uppy recognizes these plugin types (used by Dashboard for layout):

- `acquirer`: File source plugins (local, webcam, remote)
- `uploader`: Upload destination plugins
- `progressindicator`: Progress display plugins
- `editor`: File editing plugins
- `presenter`: Dashboard-like container plugins
- `modifier`: File transformation plugins

### Plugin State Management

**Global State Access**:
```javascript
const allFiles = this.uppy.getState().files
```

**Plugin-Specific State**:
```javascript
this.setPluginState({ isOpen: true })
const pluginState = this.getPluginState()
```

**File State Modification**:
```javascript
this.uppy.setFileState(fileID, {
  name: 'new-name.jpg',
  meta: { ...file.meta, customField: 'value' }
})
```

### Internationalization (i18n)

Define strings with plural support:

```javascript
this.defaultLocale = {
  strings: {
    youCanOnlyUploadX: {
      0: 'You can only upload %{smart_count} file',
      1: 'You can only upload %{smart_count} files'
    }
  }
}

this.i18nInit()  // Call in constructor
```

Override via `locale` option:
```javascript
uppy.use(MyPlugin, {
  locale: {
    strings: {
      youCanOnlyUploadX: 'Maximum %{smart_count} files'
    }
  }
})
```

---

## Uploader Implementations

### Tus (Resumable Uploads)

**Protocol**: Open standard for resumable uploads over HTTP
**Package**: `@uppy/tus`
**Key Features**:
- Automatic resume after network failures
- HTTP PATCH-based upload
- Exponential backoff on errors
- Chunk-based transmission

**Configuration**:
```javascript
uppy.use(Tus, {
  endpoint: 'https://tusd.tusdemo.net/files/',
  chunkSize: 5 * 1024 * 1024,  // 5 MiB chunks
  retryDelays: [0, 1000, 3000, 5000],
  headers: {},
  limit: 20,  // Concurrent uploads
  withCredentials: false,
  allowedMetaFields: null  // All fields
})
```

**Resume Mechanism**:
- Server assigns unique upload ID
- Client stores ID + offset
- On reconnect, client queries offset via HEAD request
- Upload continues from last received byte

### AWS S3

**Package**: `@uppy/aws-s3`
**Upload Modes**: Single-part, Multipart
**Architecture**: Client-to-storage (direct uploads)

#### Single-Part Upload

For files ≤ 100 MiB (default threshold):

```javascript
uppy.use(AwsS3, {
  getUploadParameters(file) {
    return fetch('/s3/params', {
      method: 'POST',
      body: JSON.stringify({ filename: file.name })
    })
    .then(res => res.json())
    .then(data => ({
      method: 'PUT',
      url: data.presignedUrl,
      headers: {
        'Content-Type': file.type
      }
    }))
  }
})
```

#### Multipart Upload

For files > 100 MiB:

**Flow**:
1. `createMultipartUpload()` → Get uploadId
2. Split file into chunks (5 MiB minimum)
3. `signPart()` → Get presigned URL for each part
4. Upload parts in parallel (configurable concurrency)
5. `listParts()` → Verify uploaded parts
6. `completeMultipartUpload()` → Finalize

**Configuration**:
```javascript
uppy.use(AwsS3, {
  createMultipartUpload(file) {
    // Create multipart upload
    return { uploadId, key }
  },

  signPart(file, partData) {
    // Sign individual part
    return { url, headers }
  },

  completeMultipartUpload(file, { uploadId, key, parts }) {
    // Complete upload
    return { location }
  },

  abortMultipartUpload(file, { uploadId, key }) {
    // Cleanup on failure
  },

  listParts(file, { uploadId, key }) {
    // Get already uploaded parts (for resume)
    return parts[]
  },

  getChunkSize(file) {
    return 5 * 1024 * 1024  // 5 MiB
  },

  shouldUseMultipart(file) {
    return file.size > 100 * 1024 * 1024  // 100 MiB
  },

  limit: 6,  // Parallel files
  retryDelays: [0, 1000, 3000, 5000]
})
```

**Temporary Credentials Mode**:
```javascript
uppy.use(AwsS3, {
  getTemporarySecurityCredentials() {
    return fetch('/s3/credentials')
      .then(res => res.json())
      .then(data => ({
        accessKeyId: data.AccessKeyId,
        secretAccessKey: data.SecretAccessKey,
        sessionToken: data.SessionToken,
        region: 'us-east-1',
        bucket: 'my-bucket'
      }))
  }
})
```

**Benefits**: ~20% faster (no backend signing), reduced server load

### XHR Upload

**Package**: `@uppy/xhr-upload`
**Use Case**: Traditional HTTP form uploads
**Protocol**: Standard XMLHttpRequest

**Configuration**:
```javascript
uppy.use(XHRUpload, {
  endpoint: 'https://api.example.com/upload',
  method: 'POST',
  formData: true,
  fieldName: 'files[]',
  headers: {},
  bundle: false,  // Upload individually
  limit: 5,
  timeout: 30 * 1000,
  withCredentials: false,
  allowedMetaFields: null,

  getResponseData(responseText, response) {
    return { url: JSON.parse(responseText).url }
  },

  onBeforeRequest(xhr, { file }) {
    // Modify request before sending
  },

  onAfterResponse(xhr, { file }) {
    // Handle response
  }
})
```

**Bundle Mode**:
```javascript
uppy.use(XHRUpload, {
  bundle: true,  // Single request for all files
  formData: true
})
```

---

## Configuration & Options

### Core Options

#### Upload Behavior

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `id` | string | `'uppy'` | Unique instance identifier |
| `autoProceed` | boolean | `false` | Auto-upload on file add |
| `allowMultipleUploadBatches` | boolean | `true` | Allow sequential uploads |
| `debug` | boolean | `false` | Enable debug logging |
| `logger` | object | `justErrorsLogger` | Custom logger |

#### Restrictions

```javascript
{
  restrictions: {
    maxFileSize: 1024 * 1024 * 100,      // 100 MiB per file
    minFileSize: null,
    maxTotalFileSize: null,               // All files combined
    maxNumberOfFiles: 10,
    minNumberOfFiles: null,
    allowedFileTypes: ['image/*', '.jpg', '.jpeg', '.png'],
    requiredMetaFields: ['name'],         // Enforce metadata
  }
}
```

**File Type Formats**:
- MIME type: `'image/jpeg'`
- MIME wildcard: `'image/*'`
- Extension: `'.jpg'`

#### Metadata

```javascript
{
  meta: {
    projectId: '12345',
    userId: 'abc',
    customField: 'value'
  }
}
```

Merged with each file's metadata.

#### Callbacks

```javascript
{
  onBeforeFileAdded(currentFile, files) {
    // Validate/modify before adding
    // Return false to reject
    // Return modified file to change
    if (currentFile.size > 1000000) {
      return false
    }
    return {
      ...currentFile,
      name: 'prefixed-' + currentFile.name
    }
  },

  onBeforeUpload(files) {
    // Final check before upload
    // Return false to prevent upload
    if (Object.keys(files).length < 2) {
      return false
    }
  }
}
```

#### Notifications

```javascript
{
  infoTimeout: 5000,  // Milliseconds to show notifications
}
```

#### State Store

```javascript
{
  store: myReduxStore  // Custom state management
}
```

---

## API Reference

### File Management

#### addFile(fileObject)

Add single file to state.

**Parameters**:
```javascript
uppy.addFile({
  name: 'photo.jpg',
  type: 'image/jpeg',
  data: fileBlob,
  source: 'Local',
  isRemote: false,
  meta: {
    customField: 'value'
  }
})
```

**Returns**: `fileID` (string)

#### addFiles(arrayOfFileObjects)

Add multiple files.

**Returns**: void

#### removeFile(fileID)

Remove file and cancel ongoing uploads.

#### getFile(fileID)

Retrieve file object.

**Returns**: File object or undefined

#### getFiles()

Get all files.

**Returns**: Array of file objects

#### clear()

Remove all files and reset state.

### Upload Control

#### upload()

Start upload for all added files.

**Returns**: Promise
```javascript
uppy.upload()
  .then((result) => {
    console.log('Successful uploads:', result.successful)
    console.log('Failed uploads:', result.failed)
  })
```

#### pauseResume(fileID)

Toggle pause/resume for specific file.

#### pauseAll()

Pause all uploads.

#### resumeAll()

Resume all paused uploads.

#### retryUpload(fileID)

Retry failed upload.

#### retryAll()

Retry all failed uploads.

#### cancelAll()

Cancel uploads and remove all files.

### State Management

#### setState(patch)

Merge patch into state.

```javascript
uppy.setState({
  meta: { userId: '123' }
})
```

#### getState()

Get current state snapshot.

#### setFileState(fileID, patch)

Update individual file state.

```javascript
uppy.setFileState(fileID, {
  name: 'new-name.jpg',
  meta: { ...file.meta, edited: true }
})
```

### Metadata

#### setMeta(data)

Update global metadata.

```javascript
uppy.setMeta({ projectId: '456' })
```

#### setFileMeta(fileID, data)

Update file-specific metadata.

```javascript
uppy.setFileMeta(fileID, { caption: 'Sunset photo' })
```

### Plugin Management

#### use(plugin, opts)

Install plugin.

```javascript
uppy.use(Dashboard, {
  target: '#uppy',
  inline: true
})
```

#### removePlugin(instance)

Uninstall plugin.

```javascript
const dashboard = uppy.getPlugin('Dashboard')
uppy.removePlugin(dashboard)
```

#### getPlugin(id)

Retrieve plugin instance by ID.

### Notifications

#### info(message, type, duration)

Show notification.

```javascript
uppy.info('Upload complete!', 'success', 3000)
```

**Types**: `'info'`, `'warning'`, `'error'`, `'success'`

### Utilities

#### log(message, type)

Log message.

**Types**: `'debug'`, `'warning'`, `'error'`

#### logout()

Call logout on all remote provider plugins.

#### destroy()

Cleanup: uninstall plugins, remove listeners, reset state.

---

## Fluppy Mapping Strategy

### Architecture Mapping

| Uppy Concept | Fluppy Implementation | Status |
|--------------|----------------------|--------|
| Uppy Core | `Fluppy` class | ✅ Implemented |
| BasePlugin | `Uploader` abstract class | ✅ Implemented |
| UIPlugin | Not needed (Flutter has widgets) | N/A |
| Tus Uploader | `TusUploader` | ❌ Not implemented |
| S3 Uploader | `S3Uploader` | ✅ Implemented |
| XHR Upload | `HttpUploader` | ❌ Not implemented |
| Event System | Sealed class events + Stream | ✅ Implemented |
| State Management | Internal state + getters | ✅ Implemented |

### API Mapping

| Uppy API | Fluppy API | Notes |
|----------|------------|-------|
| `addFile(obj)` | `addFile(FluppyFile)` | ✅ Implemented |
| `addFiles(arr)` | `addFiles(List<FluppyFile>)` | ✅ Implemented |
| `removeFile(id)` | `removeFile(String id)` | ✅ Implemented |
| `getFile(id)` | `getFile(String id)` | ✅ Implemented |
| `getFiles()` | `files` getter | ✅ Implemented |
| `upload()` | `upload()` | ✅ Implemented |
| `pauseAll()` | `pauseAll()` | ✅ Implemented |
| `resumeAll()` | `resumeAll()` | ✅ Implemented |
| `cancelAll()` | `cancelAll()` | ✅ Implemented |
| `retryAll()` | `retryAll()` | ✅ Implemented |
| `setState()` | N/A (internal) | State management is internal |
| `on()` | `events` stream | ✅ Stream-based |
| `destroy()` | `dispose()` | ✅ Implemented |

### Event Mapping

| Uppy Event | Fluppy Event | Class |
|------------|--------------|-------|
| `file-added` | `FileAdded` | ✅ |
| `file-removed` | `FileRemoved` | ✅ |
| `upload` | `UploadStarted` | ✅ |
| `upload-progress` | `UploadProgress` | ✅ |
| `upload-success` | `UploadComplete` | ✅ |
| `upload-error` | `UploadError` | ✅ |
| `upload-pause` | `UploadPaused` / `UploadResumed` | ✅ |
| `upload-retry` | `UploadRetry` | ✅ |
| `complete` | `AllUploadsComplete` | ✅ |
| `cancel-all` | `UploadCancelled` | ✅ |
| `preprocess-progress` | ❌ Not implemented | Need preprocessing |
| `postprocess-progress` | ❌ Not implemented | Need postprocessing |

### Feature Parity Checklist

#### Core Features

- [x] File management (add, remove, batch operations)
- [x] Event-driven architecture
- [x] Progress tracking
- [x] Pause/resume/cancel
- [x] Retry logic with delays
- [x] Concurrent upload limits
- [x] File metadata support
- [x] Lifecycle management (dispose)

#### Upload Features

- [x] S3 single-part upload
- [x] S3 multipart upload
- [x] Presigned URL support
- [x] Temporary credentials (STS)
- [x] AWS Signature V4
- [x] Chunk upload
- [x] Resume capability (list parts)
- [x] Abort multipart
- [ ] Tus protocol
- [ ] XHR/HTTP upload
- [ ] GCS upload
- [ ] Azure Blob Storage

#### Advanced Features

- [ ] Preprocessing pipeline
- [ ] Postprocessing pipeline
- [ ] Plugin system (extensible architecture)
- [ ] Multiple uploader plugins
- [ ] Remote file sources (Google Drive, Dropbox)
- [ ] Webcam capture
- [ ] URL import
- [ ] File restrictions validation
- [ ] i18n support
- [ ] Custom state store
- [ ] Golden Retriever (state recovery)

#### Platform Features

- [x] Dart (server/CLI support)
- [ ] Flutter (mobile/web UI)
- [ ] Web platform support (dart:html bridge)
- [ ] Cross-platform file picker
- [ ] Platform-specific optimizations

### Gaps & Recommendations

#### High Priority

1. **Add Preprocessing/Postprocessing Pipeline**
   - Essential for image compression, validation, post-upload workflows
   - Core to Uppy's architecture

2. **Implement Tus Uploader**
   - Most important feature after S3
   - Universal resumable upload standard

3. **Add File Restrictions**
   - `maxFileSize`, `minFileSize`, `allowedFileTypes`, etc.
   - Critical for validation

4. **Implement XHR/HTTP Uploader**
   - Basic uploader for simple backends
   - Most common use case after S3

#### Medium Priority

5. **Plugin System Refactor**
   - Make uploader registration more flexible
   - Allow multiple uploaders in one instance
   - Support uploader selection per file

6. **Flutter Integration**
   - File picker integration
   - UI components (optional)
   - Platform-specific handling

7. **State Recovery (Golden Retriever)**
   - Save state to persistent storage
   - Resume uploads after app restart

8. **More Tests**
   - S3Uploader integration tests
   - AWS Signature V4 tests
   - End-to-end scenarios

#### Low Priority

9. **Remote Sources**
   - Google Drive, Dropbox plugins
   - Requires Companion server

10. **UI Components**
    - Flutter Dashboard widget
    - Progress indicators
    - File list views

### Naming Conventions

**Keep Similar to Uppy**:
- Core class: `Uppy` → `Fluppy` ✅
- Methods: `addFile`, `removeFile`, `upload`, etc. ✅
- Events: `file-added` → `FileAdded`, etc. ✅
- Options: `retryDelays`, `limit`, etc. ✅

**Dart Conventions**:
- Use `UpperCamelCase` for classes
- Use `lowerCamelCase` for methods/properties
- Use sealed classes for events (type-safe sum types)
- Use streams instead of EventEmitter

---

## References

### Official Documentation
- [Uppy Documentation](https://uppy.io/docs/)
- [Uppy Core API](https://uppy.io/docs/uppy/)
- [Building Plugins](https://uppy.io/docs/guides/building-plugins/)
- [GitHub Repository](https://github.com/transloadit/uppy)

### Key Sources
- [Tus Protocol](https://uppy.io/docs/tus/)
- [AWS S3 Uploader](https://uppy.io/docs/aws-s3/)
- [XHR Upload](https://uppy.io/docs/xhr-upload/)

### Related Standards
- [Tus Resumable Upload Protocol](https://tus.io/protocols/resumable-upload.html)
- [AWS S3 Multipart Upload](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html)

---

## Conclusion

Fluppy has established a **solid foundation** with:
- Core orchestrator pattern
- Event-driven architecture
- Complete S3 support (single + multipart)
- Progress tracking and lifecycle management

**Next steps** for 1:1 Uppy parity:
1. Add preprocessing/postprocessing pipelines
2. Implement Tus uploader
3. Add file restrictions
4. Build HTTP/XHR uploader
5. Expand plugin system

This document should serve as the **single source of truth** for architectural decisions and feature implementation.
