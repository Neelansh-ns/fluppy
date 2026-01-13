import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluppy/fluppy.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fluppy S3 Upload Example',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), useMaterial3: true),
      home: const S3UploadPage(),
    );
  }
}

class S3UploadPage extends StatefulWidget {
  const S3UploadPage({super.key});

  @override
  State<S3UploadPage> createState() => _S3UploadPageState();
}

class _S3UploadPageState extends State<S3UploadPage> {
  // Backend server URL - update this to match your server
  final String backendUrl = 'http://localhost:3000';

  // S3 upload configuration
  // Note: Web browsers limit concurrent connections per domain to ~6-8
  // Higher values cause queueing and severe performance degradation
  final int _maxConcurrentParts = kIsWeb ? 6 : 20; // 6 for web, 20 for native
  final int _multipartThresholdMB = 10; // Files > 10MB use multipart
  final int _chunkSizeMB = 5; // 5MB per part

  Fluppy? _fluppy;
  final List<UploadFileInfo> _files = [];
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _initializeFluppy();
  }

  void _initializeFluppy() {
    _fluppy = Fluppy(
      uploader: S3Uploader(
        options: S3UploaderOptions(
          // Use multipart for files > threshold
          shouldUseMultipart: (file) => file.size > _multipartThresholdMB * 1024 * 1024,
          maxConcurrentParts: _maxConcurrentParts,

          // Chunk size for multipart uploads
          getChunkSize: (file) => _chunkSizeMB * 1024 * 1024,

          // Single-part: Get presigned URL from backend
          getUploadParameters: (file, options) async {
            final response = await http.post(
              Uri.parse('$backendUrl/presign-upload'),
              body: jsonEncode({'filename': file.name, 'contentType': file.type}),
              headers: {'Content-Type': 'application/json'},
            );

            if (response.statusCode != 200) {
              throw Exception('Failed to get presigned URL: ${response.body}');
            }

            final data = jsonDecode(response.body);

            return UploadParameters(
              method: 'PUT',
              url: data['url'],
              headers: {'Content-Type': file.type ?? 'application/octet-stream'},
            );
          },

          // Multipart: Create upload
          createMultipartUpload: (file) async {
            final response = await http.post(
              Uri.parse('$backendUrl/multipart/create'),
              body: jsonEncode({'filename': file.name, 'contentType': file.type}),
              headers: {'Content-Type': 'application/json'},
            );

            if (response.statusCode != 200) {
              throw Exception('Failed to create multipart upload: ${response.body}');
            }

            final data = jsonDecode(response.body);

            return CreateMultipartUploadResult(uploadId: data['uploadId'], key: data['key']);
          },

          // Multipart: Sign part
          signPart: (file, opts) async {
            final response = await http.post(
              Uri.parse('$backendUrl/multipart/sign-part'),
              body: jsonEncode({'key': opts.key, 'uploadId': opts.uploadId, 'partNumber': opts.partNumber}),
              headers: {'Content-Type': 'application/json'},
            );

            if (response.statusCode != 200) {
              throw Exception('Failed to sign part: ${response.body}');
            }

            final data = jsonDecode(response.body);

            return SignPartResult(url: data['url']);
          },

          // Multipart: List parts
          listParts: (file, opts) async {
            final response = await http.post(
              Uri.parse('$backendUrl/multipart/list-parts'),
              body: jsonEncode({'key': opts.key, 'uploadId': opts.uploadId}),
              headers: {'Content-Type': 'application/json'},
            );

            if (response.statusCode != 200) {
              throw Exception('Failed to list parts: ${response.body}');
            }

            final data = jsonDecode(response.body);
            final parts = (data['parts'] as List)
                .map((p) => S3Part(partNumber: p['partNumber'], size: p['size'], eTag: p['eTag']))
                .toList();

            return parts;
          },

          // Multipart: Complete
          completeMultipartUpload: (file, opts) async {
            final response = await http.post(
              Uri.parse('$backendUrl/multipart/complete'),
              body: jsonEncode({
                'key': opts.key,
                'uploadId': opts.uploadId,
                'parts': opts.parts.map((p) => {'PartNumber': p.partNumber, 'ETag': p.eTag}).toList(),
              }),
              headers: {'Content-Type': 'application/json'},
            );

            if (response.statusCode != 200) {
              throw Exception('Failed to complete multipart upload: ${response.body}');
            }

            final data = jsonDecode(response.body);

            return CompleteMultipartResult(location: data['location']);
          },

          // Multipart: Abort
          abortMultipartUpload: (file, opts) async {
            await http.post(
              Uri.parse('$backendUrl/multipart/abort'),
              body: jsonEncode({'key': opts.key, 'uploadId': opts.uploadId}),
              headers: {'Content-Type': 'application/json'},
            );
          },
        ),
      ),
      maxConcurrent: 30,
    );

    // Listen to events
    _fluppy!.events.listen((event) {
      debugLog('📢 Fluppy event received: $event');
      setState(() {
        switch (event) {
          case FileAdded(:final file):
            debugLog('📁 FileAdded event: ${file.name} (id: ${file.id})');
            _addFile(file);
            debugLog('📁 File added to UI list. Total files: ${_files.length}');
          case UploadStarted(:final file):
            final sizeStr = _formatBytes(file.size);
            _updateFile(file.id, status: 'Starting upload... (0 / $sizeStr)');
          case UploadProgress(:final file, :final progress):
            // Don't update status if file is paused - in-flight parts may still report progress
            if (file.status == FileStatus.paused) {
              break;
            }
            String statusMsg;
            if (file.isMultipart) {
              // For multipart: show parts progress, concurrency, and data progress
              final partsUploaded = progress.partsUploaded ?? 0;
              final partsTotal = progress.partsTotal ?? 0;
              final partsRemaining = partsTotal - partsUploaded;
              final activeParts = partsRemaining < _maxConcurrentParts ? partsRemaining : _maxConcurrentParts;
              final percentComplete = progress.percent.toStringAsFixed(1);
              statusMsg =
                  '$partsUploaded/$partsTotal parts • $activeParts uploading ⚡ • $percentComplete% • ${_formatBytes(progress.bytesUploaded)}/${_formatBytes(progress.bytesTotal)}';
            } else {
              // For single-part: show data progress
              final percentComplete = progress.percent.toStringAsFixed(1);
              statusMsg =
                  '$percentComplete% • ${_formatBytes(progress.bytesUploaded)}/${_formatBytes(progress.bytesTotal)}';
            }
            _updateFile(file.id, progress: progress.percent, status: statusMsg);
          case S3PartUploaded(:final file, :final totalParts):
            // Don't update status if file is paused - keep showing "Paused" status
            if (file.status == FileStatus.paused) {
              // File was paused - this is an in-flight part that completed
              // Don't update the status, keep showing "Paused"
              break;
            }
            // Use the same format as UploadProgress for consistency
            final uploadedCount = file.uploadedParts.length;
            final partsRemaining = totalParts - uploadedCount;
            final activeParts = partsRemaining < _maxConcurrentParts ? partsRemaining : _maxConcurrentParts;
            // Get progress info from file to maintain consistent format
            final progress = file.progress;
            String statusMsg;
            if (progress != null) {
              final percentComplete = progress.percent.toStringAsFixed(1);
              if (partsRemaining > 0) {
                statusMsg =
                    '$uploadedCount/$totalParts parts • $activeParts uploading ⚡ • $percentComplete% • ${_formatBytes(progress.bytesUploaded)}/${_formatBytes(progress.bytesTotal)}';
              } else {
                statusMsg =
                    '$uploadedCount/$totalParts parts • Finalizing... • $percentComplete% • ${_formatBytes(progress.bytesUploaded)}/${_formatBytes(progress.bytesTotal)}';
              }
            } else {
              // Fallback if progress is not available
              statusMsg = partsRemaining > 0
                  ? '$uploadedCount/$totalParts parts • $activeParts uploading ⚡'
                  : '$uploadedCount/$totalParts parts • Finalizing...';
            }
            _updateFile(file.id, status: statusMsg);
          case UploadPaused(:final file):
            final uploadedCount = file.uploadedParts.length;
            // Calculate total parts from file size and chunk size
            final totalParts = file.progress?.partsTotal ?? (file.size / (_chunkSizeMB * 1024 * 1024)).ceil();
            _updateFile(file.id, status: 'Paused ($uploadedCount/$totalParts parts uploaded)');
            // Check if there are any active uploads remaining
            _checkAndUpdateUploadingState();
          case UploadResumed(:final file):
            final uploadedCount = file.uploadedParts.length;
            // Calculate total parts from file size and chunk size
            final totalParts = file.progress?.partsTotal ?? (file.size / (_chunkSizeMB * 1024 * 1024)).ceil();
            _updateFile(file.id, status: 'Resuming ($uploadedCount/$totalParts parts uploaded)');
            // Show snackbar when UploadResumed event is emitted (not when resume() completes)
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Resumed: ${file.name}')));
            }
          case UploadComplete(:final file, :final response):
            String completeMsg = 'Complete';
            if (file.isMultipart) {
              final totalParts = file.uploadedParts.length;
              completeMsg = '✓ Complete ($totalParts parts uploaded)';
            }
            _updateFile(file.id, status: completeMsg, progress: 100.0, location: response?.location);
          case UploadError(:final file, :final message):
            _updateFile(file.id, status: 'Error: $message', hasError: true);
          case UploadCancelled(:final file):
            _updateFile(file.id, status: 'Cancelled');
            // Check if there are any active uploads remaining
            _checkAndUpdateUploadingState();
          case AllUploadsComplete(:final successful, :final failed):
            setState(() {
              _isUploading = false;
            });
            // Only show dialog if there are actually completed or failed files
            // (don't show for paused uploads where successful=0, failed=0)
            if (successful.isNotEmpty || failed.isNotEmpty) {
              _showCompletionDialog(successful.length, failed.length);
            }
          default:
            break;
        }
      });
    });
  }

  void _addFile(FluppyFile file) {
    debugLog('🎯 _addFile called: ${file.name} (id: ${file.id})');
    _files.add(UploadFileInfo(id: file.id, name: file.name, size: file.size, status: 'Ready', progress: 0.0));
    debugLog('✅ File added to _files list. Total: ${_files.length}');
  }

  void _updateFile(String id, {String? status, double? progress, String? location, bool? hasError}) {
    final index = _files.indexWhere((f) => f.id == id);
    if (index != -1) {
      _files[index] = _files[index].copyWith(
        status: status,
        progress: progress,
        location: location,
        hasError: hasError,
      );
    }
  }

  Future<void> _pickFiles() async {
    debugLog('=== _pickFiles called ===');
    debugLog('Platform: kIsWeb = $kIsWeb');

    try {
      debugLog('Calling FilePicker.platform.pickFiles...');
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: kIsWeb, // Load bytes on web
      );

      debugLog('FilePicker result: ${result != null ? "Success (${result.files.length} files)" : "Cancelled/null"}');

      if (result != null) {
        for (final platformFile in result.files) {
          debugLog('Processing file: ${platformFile.name}');
          if (kIsWeb) {
            // On web, use bytes (path is not available)
            if (platformFile.bytes != null) {
              debugLog('  -> Using bytes (${platformFile.bytes!.length} bytes)');
              final file = FluppyFile.fromBytes(
                platformFile.bytes!,
                name: platformFile.name,
                type: _getMimeType(platformFile.extension),
              );
              _fluppy!.addFile(file);
            } else {
              debugLog('  -> ERROR: bytes is null on web!');
            }
          } else {
            // On mobile/desktop, use path
            if (platformFile.path != null) {
              debugLog('  -> Using path: ${platformFile.path}');
              try {
                final file = FluppyFile.fromPath(
                  platformFile.path!,
                  name: platformFile.name,
                  type: _getMimeType(platformFile.extension),
                );
                debugLog('📤 Calling addFile for: ${file.name} (id: ${file.id}, size: ${file.size})');
                final addedFile = _fluppy!.addFile(file);
                debugLog('✅ addFile returned: ${addedFile.name} (id: ${addedFile.id})');
              } catch (e, stackTrace) {
                debugLog('❌ ERROR creating/adding file: $e');
                debugLog('Stack trace: $stackTrace');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error adding file: $e'), duration: const Duration(seconds: 5)),
                  );
                }
              }
            } else {
              debugLog('  -> ERROR: path is null on native!');
            }
          }
        }
        debugLog('=== _pickFiles completed successfully ===');
      } else {
        debugLog('=== _pickFiles cancelled by user ===');
      }
    } catch (e, stackTrace) {
      debugLog('=== ERROR in _pickFiles ===');
      debugLog('Error: $e');
      debugLog('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('File picker error: $e'), duration: const Duration(seconds: 5)));
      }
    }
  }

  Future<void> _uploadAll() async {
    setState(() {
      _isUploading = true;
    });

    try {
      await _fluppy!.upload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload error: $e')));
      }
    }
  }

  Future<void> _pauseFile(String id) async {
    final file = _fluppy!.files.firstWhere((f) => f.id == id);
    await _fluppy!.pause(id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Paused: ${file.name}')));
    }
  }

  Future<void> _resumeFile(String id) async {
    await _fluppy!.resume(id);
    // Note: Snackbar is now shown in the UploadResumed event handler, not here
    // This ensures it appears immediately when resume() is called, not when it completes
  }

  Future<void> _retryFile(String id) async {
    final file = _fluppy!.files.firstWhere((f) => f.id == id);
    await _fluppy!.retry(id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Retrying: ${file.name}')));
    }
  }

  Future<void> _removeFile(String id) async {
    final fileInfo = _files.firstWhere((f) => f.id == id);
    final file = _fluppy!.files.firstWhere((f) => f.id == id);

    // Check if file is currently uploading
    final isUploading = file.status == FileStatus.uploading;

    if (isUploading) {
      // Show confirmation dialog for active uploads
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancel Upload?'),
          content: Text('Are you sure you want to cancel uploading "${fileInfo.name}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Cancel')),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    // Remove file (will cancel upload if in progress)
    await _fluppy!.removeFile(id);

    setState(() {
      _files.removeWhere((f) => f.id == id);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isUploading ? 'Cancelled: ${fileInfo.name}' : 'Removed: ${fileInfo.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _clearAll() {
    _fluppy!.cancelAll();
    setState(() {
      _files.clear();
      _isUploading = false;
    });
  }

  void _checkAndUpdateUploadingState() {
    // Check if there are any files currently uploading
    final hasActiveUploads = _fluppy!.files.any((file) => file.status == FileStatus.uploading);
    if (!hasActiveUploads && _isUploading) {
      setState(() {
        _isUploading = false;
      });
    }
  }

  bool _canUploadAnyFile() {
    if (_files.isEmpty || _fluppy == null) return false;
    // Check if any file is ready to start uploading (pending status only)
    // Paused files should use Resume, error files should use Retry
    return _fluppy!.files.any((file) => file.status == FileStatus.pending);
  }

  void _showCompletionDialog(int successful, int failed) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload Complete'),
        content: Text('Successful: $successful\nFailed: $failed'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  String _getMimeType(String? extension) {
    if (extension == null) return 'application/octet-stream';
    final ext = extension.toLowerCase();
    final mimeTypes = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'zip': 'application/zip',
    };
    return mimeTypes[ext] ?? 'application/octet-stream';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  void dispose() {
    _fluppy?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fluppy S3 Upload Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_files.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete_sweep), onPressed: _clearAll, tooltip: 'Clear all'),
        ],
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Make sure the backend server is running on $backendUrl',
                    style: const TextStyle(color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),

          // File list
          Expanded(
            child: _files.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_upload_outlined, size: 80, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text('No files selected', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                        const SizedBox(height: 8),
                        Text('Tap the + button to add files', style: TextStyle(color: Colors.grey.shade500)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      return FileListItem(
                        file: file,
                        onPause: () => _pauseFile(file.id),
                        onResume: () => _resumeFile(file.id),
                        onRetry: () => _retryFile(file.id),
                        onRemove: () => _removeFile(file.id),
                      );
                    },
                  ),
          ),

          // Action buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, -2)),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Files'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: !_canUploadAnyFile() ? null : _uploadAll,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(_isUploading ? 'Uploading...' : 'Upload All'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class UploadFileInfo {
  final String id;
  final String name;
  final int size;
  final String status;
  final double progress;
  final String? location;
  final bool hasError;

  UploadFileInfo({
    required this.id,
    required this.name,
    required this.size,
    required this.status,
    required this.progress,
    this.location,
    this.hasError = false,
  });

  UploadFileInfo copyWith({String? status, double? progress, String? location, bool? hasError}) {
    return UploadFileInfo(
      id: id,
      name: name,
      size: size,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      location: location ?? this.location,
      hasError: hasError ?? this.hasError,
    );
  }
}

class FileListItem extends StatelessWidget {
  final UploadFileInfo file;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  const FileListItem({
    super.key,
    required this.file,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onRemove,
  });

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    // Determine file state based on status string
    final statusLower = file.status.toLowerCase();
    final isUploading =
        statusLower.contains('uploading') ||
        statusLower.contains('starting') ||
        statusLower.contains('resuming') ||
        (file.progress > 0 &&
            file.progress < 100 &&
            !statusLower.contains('paused') &&
            !statusLower.contains('complete'));
    final isPaused = statusLower.startsWith('paused');
    final isComplete = statusLower.contains('complete');
    final hasError = file.hasError;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getFileIcon(),
                  color: hasError
                      ? Colors.red
                      : isComplete
                      ? Colors.green
                      : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(_formatBytes(file.size), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                if (!isComplete && !hasError)
                  IconButton(
                    icon: Icon(
                      isUploading ? Icons.cancel : Icons.close,
                      size: 20,
                      color: isUploading ? Colors.orange : null,
                    ),
                    onPressed: onRemove,
                    tooltip: isUploading ? 'Cancel upload' : 'Remove',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: file.progress / 100,
              backgroundColor: Colors.grey.shade200,
              color: hasError
                  ? Colors.red
                  : isComplete
                  ? Colors.green
                  : isPaused
                  ? Colors.orange
                  : Colors.blue,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    file.status,
                    style: TextStyle(
                      fontSize: 13,
                      color: hasError
                          ? Colors.red
                          : isComplete
                          ? Colors.green
                          : isPaused
                          ? Colors.orange
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
                if (isUploading)
                  TextButton.icon(
                    onPressed: onPause,
                    icon: const Icon(Icons.pause, size: 16),
                    label: const Text('Pause'),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                  ),
                if (isPaused)
                  TextButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Resume'),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                  ),
                if (hasError)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                  ),
              ],
            ),
            if (file.location != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        file.location!,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: file.location!));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('URL copied to clipboard'), duration: Duration(seconds: 2)),
                          );
                        }
                      },
                      tooltip: 'Copy URL',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: Colors.green,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon() {
    final ext = file.name.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp'].contains(ext)) {
      return Icons.image;
    } else if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
      return Icons.videocam;
    } else if (['mp3', 'wav', 'flac', 'aac'].contains(ext)) {
      return Icons.audiotrack;
    } else if (['pdf'].contains(ext)) {
      return Icons.picture_as_pdf;
    } else if (['doc', 'docx', 'txt'].contains(ext)) {
      return Icons.description;
    } else if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return Icons.folder_zip;
    }
    return Icons.insert_drive_file;
  }
}

/// Debug print helper that only prints in debug mode
void debugLog(String message) {
  if (kDebugMode) {
    print(message);
  }
}
