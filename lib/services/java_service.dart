import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/java_info.dart';

class JavaService extends ChangeNotifier {
  List<JavaInfo> _detectedJavas = [];
  List<String> _customJavaPaths = [];
  bool _isScanning = false;

  List<JavaInfo> get detectedJavas => List.unmodifiable(_detectedJavas);
  List<String> get customJavaPaths => List.unmodifiable(_customJavaPaths);
  bool get isScanning => _isScanning;

  static const _excludeFolderNames = {'javapath', 'java8path', 'common files'};
  
  static const _javaKeywords = [
    'java', 'jdk', 'jre', 'dragonwell', 'azul', 'zulu', 'oracle', 'open',
    'amazon', 'corretto', 'eclipse', 'temurin', 'hotspot', 'semeru', 
    'kona', 'bellsoft', 'liberica', 'graalvm', 'microsoft', 'adoptium'
  ];

  Future<void> init() async {
    await _loadFromCache();
    await _loadCustomJavas();
    if (_detectedJavas.isEmpty) {
      await scanJava();
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList('cached_java_paths') ?? [];
      if (cached.isEmpty) return;
      
      final validJavas = <JavaInfo>[];
      for (final path in cached) {
        if (await File(path).exists()) {
          final info = await JavaInfo.fromPath(path);
          if (info != null) {
            validJavas.add(info);
          }
        }
      }
      
      if (validJavas.isNotEmpty) {
        _detectedJavas = validJavas;
        _sortJavas();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load Java cache: $e');
    }
  }

  Future<void> _loadCustomJavas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _customJavaPaths = prefs.getStringList('custom_java_paths') ?? [];
    } catch (e) {
      debugPrint('Failed to load custom Java paths: $e');
    }
  }

  Future<void> _saveCustomJavas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('custom_java_paths', _customJavaPaths);
    } catch (e) {
      debugPrint('Failed to save custom Java paths: $e');
    }
  }

  Future<bool> addCustomJava(String path) async {
    if (_customJavaPaths.contains(path)) return false;
    
    final info = await JavaInfo.fromPath(path);
    if (info == null) return false;
    
    _customJavaPaths.add(path);
    await _saveCustomJavas();
    
    if (!_detectedJavas.any((j) => j.path == path)) {
      _detectedJavas.add(info);
      _sortJavas();
      await _saveToCache();
    }
    
    notifyListeners();
    return true;
  }

  Future<void> removeCustomJava(String path) async {
    _customJavaPaths.remove(path);
    await _saveCustomJavas();
    notifyListeners();
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paths = _detectedJavas.map((j) => j.path).toList();
      await prefs.setStringList('cached_java_paths', paths);
    } catch (e) {
      debugPrint('Failed to save Java cache: $e');
    }
  }

  void _sortJavas() {
    _detectedJavas.sort((a, b) {
      final versionCompare = b.majorVersion.compareTo(a.majorVersion);
      if (versionCompare != 0) return versionCompare;
      return a.brand.index.compareTo(b.brand.index);
    });
  }

  Future<void> scanJava() async {
    if (_isScanning) return;
    
    _isScanning = true;
    notifyListeners();

    final javaPaths = <String>{};

    try {
      await Future.wait([
        _scanPathEnvironment(javaPaths),
        _scanJavaHome(javaPaths),
        _scanDefaultInstallPaths(javaPaths),
        _scanMicrosoftStoreJava(javaPaths),
        _scanFromWhereCommand(javaPaths),
      ]);

      javaPaths.addAll(_customJavaPaths);

      final filteredPaths = javaPaths.where((path) {
        final lowerPath = path.toLowerCase();
        return !_excludeFolderNames.any((name) => lowerPath.contains('\\$name\\'));
      }).toSet();

      final validJavas = <JavaInfo>[];
      final seenPaths = <String>{};
      
      for (final path in filteredPaths) {
        final normalizedPath = path.toLowerCase();
        if (seenPaths.contains(normalizedPath)) continue;
        seenPaths.add(normalizedPath);
        
        final info = await JavaInfo.fromPath(path);
        if (info != null) {
          validJavas.add(info);
        }
      }

      _detectedJavas = validJavas;
      _sortJavas();
      await _saveToCache();
    } catch (e) {
      debugPrint('Java scan error: $e');
    }

    _isScanning = false;
    notifyListeners();
  }

  Future<void> _scanPathEnvironment(Set<String> paths) async {
    final pathEnv = Platform.environment['PATH'] ?? '';
    for (final dir in pathEnv.split(';')) {
      if (dir.isEmpty) continue;
      final javaExe = p.join(dir, 'java.exe');
      if (await File(javaExe).exists()) {
        paths.add(javaExe);
      }
    }
  }

  Future<void> _scanJavaHome(Set<String> paths) async {
    final javaHome = Platform.environment['JAVA_HOME'];
    if (javaHome != null && javaHome.isNotEmpty) {
      final javaExe = p.join(javaHome, 'bin', 'java.exe');
      if (await File(javaExe).exists()) {
        paths.add(javaExe);
      }
    }
  }

  Future<void> _scanDefaultInstallPaths(Set<String> paths) async {
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    final appData = Platform.environment['APPDATA'] ?? '';
    final userProfile = Platform.environment['USERPROFILE'] ?? '';
    
    final searchPaths = <String>{
      localAppData,
      appData,
      userProfile,
    };

    for (final drive in ['C', 'D']) {
      searchPaths.add('$drive:\\Program Files');
      searchPaths.add('$drive:\\Program Files (x86)');
    }

    for (final basePath in searchPaths) {
      if (basePath.isEmpty || !await Directory(basePath).exists()) continue;
      
      try {
        await for (final entity in Directory(basePath).list()) {
          if (entity is Directory) {
            final dirName = p.basename(entity.path).toLowerCase();
            if (_javaKeywords.any((k) => dirName.contains(k))) {
              await _scanDirectoryForJava(entity.path, paths, maxDepth: 3);
            }
          }
        }
      } catch (e) {}
    }

    final specificPaths = [
      p.join(appData, '.minecraft', 'runtime'),
      p.join(userProfile, '.jdks'),
    ];
    for (final path in specificPaths) {
      await _scanDirectoryForJava(path, paths, maxDepth: 4);
    }
  }

  Future<void> _scanMicrosoftStoreJava(Set<String> paths) async {
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    final storeJavaFolder = p.join(
      localAppData, 'Packages',
      'Microsoft.4297127D64EC6_8wekyb3d8bbwe',
      'LocalCache', 'Local', 'runtime',
    );
    await _scanDirectoryForJava(storeJavaFolder, paths, maxDepth: 5);
  }

  Future<void> _scanFromWhereCommand(Set<String> paths) async {
    try {
      final result = await Process.run('where', ['java'], runInShell: true)
          .timeout(const Duration(seconds: 3));
      if (result.exitCode == 0) {
        for (final line in result.stdout.toString().split('\n')) {
          final path = line.trim();
          if (path.endsWith('.exe') && await File(path).exists()) {
            paths.add(path);
          }
        }
      }
    } catch (e) {}
  }

  Future<void> _scanDirectoryForJava(String basePath, Set<String> paths, {int maxDepth = 3}) async {
    if (!await Directory(basePath).exists()) return;
    
    final queue = <(String, int)>[(basePath, 0)];
    
    while (queue.isNotEmpty) {
      final (currentPath, depth) = queue.removeAt(0);
      if (depth > maxDepth) continue;
      
      try {
        await for (final entity in Directory(currentPath).list()) {
          if (entity is Directory) {
            final javaExe = p.join(entity.path, 'java.exe');
            if (await File(javaExe).exists()) {
              paths.add(javaExe);
            }
            
            final binJavaExe = p.join(entity.path, 'bin', 'java.exe');
            if (await File(binJavaExe).exists()) {
              paths.add(binJavaExe);
            }
            
            if (depth < maxDepth) {
              queue.add((entity.path, depth + 1));
            }
          }
        }
      } catch (e) {}
    }
  }

  JavaInfo? selectJavaForVersion(int? requiredVersion, {int? maxVersion}) {
    if (_detectedJavas.isEmpty) return null;
    if (requiredVersion == null) return _detectedJavas.first;

    if (maxVersion != null) {
      for (final java in _detectedJavas) {
        if (java.majorVersion >= requiredVersion && java.majorVersion <= maxVersion && java.is64Bit && !java.isJre) {
          return java;
        }
      }
      for (final java in _detectedJavas) {
        if (java.majorVersion >= requiredVersion && java.majorVersion <= maxVersion && java.is64Bit) {
          return java;
        }
      }
      for (final java in _detectedJavas) {
        if (java.majorVersion >= requiredVersion && java.majorVersion <= maxVersion) {
          return java;
        }
      }
    }

    for (final java in _detectedJavas) {
      if (java.majorVersion >= requiredVersion && java.is64Bit && !java.isJre) {
        return java;
      }
    }
    for (final java in _detectedJavas) {
      if (java.majorVersion >= requiredVersion && java.is64Bit) {
        return java;
      }
    }
    for (final java in _detectedJavas) {
      if (java.majorVersion >= requiredVersion) {
        return java;
      }
    }
    return _detectedJavas.first;
  }

  JavaInfo? getJavaByPath(String path) {
    return _detectedJavas.where((j) => j.path == path).firstOrNull;
  }

  static (int minVersion, int? maxVersion) getRequiredJavaVersion(String mcVersion) {
    final parts = mcVersion.split('.');
    if (parts.length < 2) return (8, null);
    
    final major = int.tryParse(parts[0]) ?? 1;
    final minor = int.tryParse(parts[1]) ?? 0;
    
    if (major >= 1 && minor >= 21) {
      return (21, null);
    }
    
    if (major >= 1 && minor >= 18) {
      return (17, null);
    }
    
    if (major >= 1 && minor >= 17) {
      return (16, null);
    }
    
    return (8, 8);
  }
}
