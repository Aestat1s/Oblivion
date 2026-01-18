import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import '../models/download_task.dart';
import 'game_service.dart';
import 'debug_logger.dart';

class DownloadService extends ChangeNotifier {
  final http.Client _client = http.Client();
  final List<DownloadGroup> _groups = [];
  bool _isDownloading = false;
  int _completedCount = 0;
  int _totalCount = 0;
  int _failedCount = 0;

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  List<DownloadGroup> get groups => List.unmodifiable(_groups);
  bool get isDownloading => _isDownloading;
  int get completedCount => _completedCount;
  int get totalCount => _totalCount;
  int get failedCount => _failedCount;
  double get progress => _totalCount > 0 ? _completedCount / _totalCount : 0;

  
  DownloadGroup createGroup(String name) {
    final group = DownloadGroup(name: name);
    _groups.add(group);
    notifyListeners();
    return group;
  }

  
  void clearCompleted() {
    _groups.removeWhere((g) => g.status == DownloadStatus.completed);
    notifyListeners();
  }

  
  void removeGroup(String groupId) {
    _groups.removeWhere((g) => g.id == groupId);
    notifyListeners();
  }

  
  Future<bool> downloadFilesInBackground(
    String groupName,
    List<DownloadFile> files,
    int concurrency, {
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  }) async {
    debugLog('[DownloadService] downloadFilesInBackground: groupName="$groupName", files=${files.length}, concurrency=$concurrency');
    
    if (files.isEmpty) {
      debugLog('[DownloadService] No files to download, returning true');
      return true;
    }

    final group = createGroup(groupName);
    debugLog('[DownloadService] Created group: ${group.id}');
    
    
    for (final file in files) {
      group.tasks.add(DownloadTask(
        name: file.path.split('/').last.split('\\').last,
        url: file.url,
        fallbackUrls: file.fallbackUrls,
        destinationPath: file.path,
        sha1: file.sha1,
        totalBytes: file.size ?? 0,
      ));
    }
    
    debugLog('[DownloadService] Added ${group.tasks.length} tasks to group');
    
    group.status = DownloadStatus.downloading;
    notifyListeners();
    debugLog('[DownloadService] Group status set to downloading, notified listeners');

    
    final success = await _downloadGroupFiles(group, concurrency, onProgress, onStatus);
    
    group.status = success ? DownloadStatus.completed : DownloadStatus.failed;
    notifyListeners();
    debugLog('[DownloadService] Download finished: success=$success, group status=${group.status}');
    
    return success;
  }

  Future<bool> _downloadGroupFiles(
    DownloadGroup group,
    int concurrency,
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  ) async {
    final semaphore = _Semaphore(concurrency);
    final futures = <Future<bool>>[];

    for (final task in group.tasks) {
      futures.add(_downloadTaskWithSemaphore(semaphore, task, group, onProgress, onStatus));
    }

    final results = await Future.wait(futures);
    return results.every((r) => r);
  }

  Future<bool> _downloadTaskWithSemaphore(
    _Semaphore semaphore,
    DownloadTask task,
    DownloadGroup group,
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  ) async {
    await semaphore.acquire();
    try {
      return await _downloadTask(task, group, onProgress, onStatus);
    } finally {
      semaphore.release();
    }
  }

  Future<bool> _downloadTask(
    DownloadTask task,
    DownloadGroup group,
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  ) async {
    task.status = DownloadStatus.downloading;
    notifyListeners();

    final outFile = File(task.destinationPath);
    
    
    if (await outFile.exists()) {
      if (task.sha1 != null) {
        final bytes = await outFile.readAsBytes();
        final hash = sha1.convert(bytes).toString();
        if (hash == task.sha1) {
          task.status = DownloadStatus.completed;
          task.downloadedBytes = bytes.length;
          task.totalBytes = bytes.length;
          onProgress?.call(group.progress / 100);
          notifyListeners();
          return true;
        }
      } else if (task.totalBytes > 0) {
        final stat = await outFile.stat();
        if (stat.size == task.totalBytes) {
          task.status = DownloadStatus.completed;
          task.downloadedBytes = stat.size;
          onProgress?.call(group.progress / 100);
          notifyListeners();
          return true;
        }
      } else {
        task.status = DownloadStatus.completed;
        final stat = await outFile.stat();
        task.downloadedBytes = stat.size;
        task.totalBytes = stat.size;
        onProgress?.call(group.progress / 100);
        notifyListeners();
        return true;
      }
    }

    
    final allUrls = [task.url, ...task.fallbackUrls];

    for (final url in allUrls) {
      for (int retry = 0; retry < 3; retry++) {
        try {
          await outFile.parent.create(recursive: true);
          
          final response = await _client.get(Uri.parse(url))
              .timeout(const Duration(seconds: 15));
              
          if (response.statusCode != 200) {
            throw Exception('HTTP ${response.statusCode}');
          }

          await outFile.writeAsBytes(response.bodyBytes);
          task.downloadedBytes = response.bodyBytes.length;
          task.totalBytes = response.bodyBytes.length;

          
          if (task.sha1 != null) {
            final hash = sha1.convert(response.bodyBytes).toString();
            if (hash != task.sha1) {
              await outFile.delete();
              throw Exception('SHA1 mismatch');
            }
          }

          task.status = DownloadStatus.completed;
          task.endTime = DateTime.now();
          onProgress?.call(group.progress / 100);
          notifyListeners();
          return true;
        } catch (e) {
          debugPrint('Download failed (attempt ${retry + 1}) for $url: $e');
          task.retryCount = retry + 1;
          
          
          if (retry == 2 && url == allUrls.last) {
            task.status = DownloadStatus.failed;
            task.errorMessage = e.toString();
            task.endTime = DateTime.now();
            notifyListeners();
            return false;
          }
          await Future.delayed(Duration(seconds: retry + 1));
        }
      }
    }

    return false;
  }

  
  Future<bool> downloadFiles(
    List<DownloadFile> files,
    int concurrency, {
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  }) async {
    if (files.isEmpty) return true;

    _isDownloading = true;
    _completedCount = 0;
    _failedCount = 0;
    _totalCount = files.length;
    notifyListeners();

    final queue = List<DownloadFile>.from(files);
    final futures = <Future<bool>>[];
    final semaphore = _Semaphore(concurrency);

    for (final file in queue) {
      futures.add(_downloadWithSemaphore(semaphore, file, onProgress, onStatus));
    }

    final results = await Future.wait(futures);
    
    _isDownloading = false;
    notifyListeners();

    return results.every((r) => r);
  }

  Future<bool> _downloadWithSemaphore(
    _Semaphore semaphore,
    DownloadFile file,
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  ) async {
    await semaphore.acquire();
    try {
      return await _downloadFile(file, onProgress, onStatus);
    } finally {
      semaphore.release();
    }
  }

  Future<bool> _downloadFile(
    DownloadFile file,
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  ) async {
    final outFile = File(file.path);
    
    
    if (await outFile.exists()) {
      if (file.sha1 != null) {
        final bytes = await outFile.readAsBytes();
        final hash = sha1.convert(bytes).toString();
        if (hash == file.sha1) {
          _completedCount++;
          onProgress?.call(progress);
          notifyListeners();
          return true;
        }
      } else if (file.size != null) {
        final stat = await outFile.stat();
        if (stat.size == file.size) {
          _completedCount++;
          onProgress?.call(progress);
          notifyListeners();
          return true;
        }
      } else {
        _completedCount++;
        onProgress?.call(progress);
        notifyListeners();
        return true;
      }
    }

    
    for (int retry = 0; retry < 3; retry++) {
      try {
        await outFile.parent.create(recursive: true);
        
        final response = await _client.get(Uri.parse(file.url))
            .timeout(const Duration(seconds: 15));
            
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }

        await outFile.writeAsBytes(response.bodyBytes);

        
        if (file.sha1 != null) {
          final hash = sha1.convert(response.bodyBytes).toString();
          if (hash != file.sha1) {
            await outFile.delete();
            throw Exception('SHA1 mismatch');
          }
        }

        _completedCount++;
        onProgress?.call(progress);
        notifyListeners();
        return true;
      } catch (e) {
        debugPrint('Download failed (attempt ${retry + 1}): ${file.url} - $e');
        if (retry == 2) {
          _failedCount++;
          notifyListeners();
          return false;
        }
        await Future.delayed(Duration(seconds: retry + 1));
      }
    }

    return false;
  }

  void cancelAll() {
    _isDownloading = false;
    for (final group in _groups) {
      if (group.status == DownloadStatus.downloading) {
        group.status = DownloadStatus.cancelled;
        for (final task in group.tasks) {
          if (task.status == DownloadStatus.downloading || 
              task.status == DownloadStatus.pending) {
            task.status = DownloadStatus.cancelled;
          }
        }
      }
    }
    notifyListeners();
  }
}

class _Semaphore {
  final int maxCount;
  int _currentCount = 0;
  final _waitQueue = <Completer<void>>[];

  _Semaphore(this.maxCount);

  Future<void> acquire() async {
    if (_currentCount < maxCount) {
      _currentCount++;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeAt(0);
      completer.complete();
    } else {
      _currentCount--;
    }
  }
}
