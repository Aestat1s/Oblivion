import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class DebugLogger {
  static final DebugLogger _instance = DebugLogger._internal();
  factory DebugLogger() => _instance;
  DebugLogger._internal();

  final List<String> _logs = [];
  static const int _maxLogs = 10000;

  Future<void> init() async {
    log('=== Oblivion Launcher Debug Log ===');
    log('Started at: ${DateTime.now()}');
    log('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  }

  void log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final line = '[$timestamp] $message';
    debugPrint(line);
    
    _logs.add(line);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }
  }

  /// 获取所有日志
  List<String> get logs => List.unmodifiable(_logs);

  /// 导出日志到文件
  Future<String> exportLogs({String? directory}) async {
    final dir = directory ?? 'D:';
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final fileName = 'oblivion_log_$timestamp.txt';
    final filePath = p.join(dir, fileName);
    
    final content = StringBuffer();
    content.writeln('=== Oblivion Launcher Log Export ===');
    content.writeln('Exported at: ${DateTime.now()}');
    content.writeln('Total entries: ${_logs.length}');
    content.writeln('');
    content.writeln('=== Log Entries ===');
    for (final log in _logs) {
      content.writeln(log);
    }
    
    await File(filePath).writeAsString(content.toString());
    log('Logs exported to: $filePath');
    return filePath;
  }

  /// 清除日志
  void clear() {
    _logs.clear();
    log('Logs cleared');
  }

  Future<void> close() async {}
}

void debugLog(String message) {
  DebugLogger().log(message);
}

