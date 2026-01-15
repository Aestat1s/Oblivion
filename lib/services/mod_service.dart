import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum ModStatus { enabled, disabled, error }

class LocalMod {
  final String path;
  final String name;
  final String fileName;
  final ModStatus status;
  final int size;
  final DateTime modifiedTime;

  LocalMod({
    required this.path,
    required this.name,
    required this.fileName,
    required this.status,
    required this.size,
    required this.modifiedTime,
  });

  static Future<LocalMod?> fromFile(File file) async {
    try {
      final stat = await file.stat();
      final fileName = p.basename(file.path);
      
      ModStatus status;
      String name;
      
      if (fileName.endsWith('.jar.disabled') || fileName.endsWith('.jar.old')) {
        status = ModStatus.disabled;
        name = fileName.replaceAll('.jar.disabled', '').replaceAll('.jar.old', '');
      } else if (fileName.endsWith('.jar')) {
        status = ModStatus.enabled;
        name = fileName.replaceAll('.jar', '');
      } else if (fileName.endsWith('.litemod')) {
        status = ModStatus.enabled;
        name = fileName.replaceAll('.litemod', '');
      } else {
        return null;
      }

      return LocalMod(
        path: file.path,
        name: name,
        fileName: fileName,
        status: status,
        size: stat.size,
        modifiedTime: stat.modified,
      );
    } catch (e) {
      return null;
    }
  }
}

class ModService extends ChangeNotifier {
  List<LocalMod> _mods = [];
  bool _isLoading = false;
  String? _currentVersionPath;
  String _searchQuery = '';

  List<LocalMod> get mods => _searchQuery.isEmpty 
      ? _mods 
      : _mods.where((m) => m.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  
  int get enabledCount => _mods.where((m) => m.status == ModStatus.enabled).length;
  int get disabledCount => _mods.where((m) => m.status == ModStatus.disabled).length;
  int get totalCount => _mods.length;

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  String getModsPath(String versionPath) => p.join(versionPath, 'mods');

  Future<void> loadMods(String versionPath) async {
    _currentVersionPath = versionPath;
    _isLoading = true;
    _mods = [];
    notifyListeners();

    try {
      final modsDir = Directory(getModsPath(versionPath));
      
      if (!await modsDir.exists()) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      final newMods = <LocalMod>[];
      
      await for (final entity in modsDir.list()) {
        if (entity is File) {
          final mod = await LocalMod.fromFile(entity);
          if (mod != null) newMods.add(mod);
        }
      }

      newMods.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _mods = newMods;
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_currentVersionPath != null) {
      await loadMods(_currentVersionPath!);
    }
  }

  Future<bool> enableMod(LocalMod mod) async {
    try {
      final file = File(mod.path);
      if (!await file.exists()) return false;

      String newPath;
      if (mod.path.endsWith('.jar.disabled')) {
        newPath = mod.path.replaceAll('.jar.disabled', '.jar');
      } else if (mod.path.endsWith('.jar.old')) {
        newPath = mod.path.replaceAll('.jar.old', '.jar');
      } else {
        return false;
      }

      if (await File(newPath).exists()) return false;

      await file.rename(newPath);
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> disableMod(LocalMod mod) async {
    try {
      final file = File(mod.path);
      if (!await file.exists()) return false;

      final newPath = '${mod.path}.disabled';
      if (await File(newPath).exists()) return false;

      await file.rename(newPath);
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleMod(LocalMod mod) async {
    if (mod.status == ModStatus.enabled) {
      return await disableMod(mod);
    } else if (mod.status == ModStatus.disabled) {
      return await enableMod(mod);
    }
    return false;
  }

  Future<bool> deleteMod(LocalMod mod) async {
    try {
      final file = File(mod.path);
      if (await file.exists()) {
        await file.delete();
        await refresh();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<int> enableMods(List<LocalMod> mods) async {
    int count = 0;
    for (final mod in mods) {
      if (mod.status == ModStatus.disabled) {
        if (await enableMod(mod)) count++;
      }
    }
    return count;
  }

  Future<int> disableMods(List<LocalMod> mods) async {
    int count = 0;
    for (final mod in mods) {
      if (mod.status == ModStatus.enabled) {
        if (await disableMod(mod)) count++;
      }
    }
    return count;
  }

  Future<int> deleteMods(List<LocalMod> mods) async {
    int count = 0;
    for (final mod in mods) {
      if (await deleteMod(mod)) count++;
    }
    return count;
  }

  Future<void> openModsFolder() async {
    if (_currentVersionPath == null) return;
    
    final modsDir = Directory(getModsPath(_currentVersionPath!));
    if (!await modsDir.exists()) {
      await modsDir.create(recursive: true);
    }
    
    if (Platform.isWindows) {
      await Process.run('explorer', [modsDir.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [modsDir.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [modsDir.path]);
    }
  }

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
