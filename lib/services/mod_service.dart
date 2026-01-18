import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/mod_info.dart';
import '../models/game_version.dart';

class ModService extends ChangeNotifier {
  final String gameDirectory;
  List<LocalMod> _mods = [];
  bool _isLoading = false;
  String? _currentVersionId;
  String _searchQuery = '';

  ModService(this.gameDirectory);

  List<LocalMod> get mods => _searchQuery.isEmpty 
      ? _mods 
      : _mods.where((m) => m.displayName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  
  int get enabledCount => _mods.where((m) => m.enabled).length;
  int get disabledCount => _mods.where((m) => !m.enabled).length;
  int get totalCount => _mods.length;

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  String getModsDir(String? versionId) {
    if (versionId == null) return p.join(gameDirectory, 'mods');
    return p.join(gameDirectory, 'versions', versionId, 'mods');
  }

  Future<void> loadMods(String? versionId) async {
    if (versionId == null) return;
    _currentVersionId = versionId;
    _isLoading = true;
    _mods = [];
    notifyListeners();

    try {
      final modsDir = Directory(getModsDir(versionId));
      
      if (!await modsDir.exists()) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      final newMods = <LocalMod>[];
      
      await for (final entity in modsDir.list()) {
        if (entity is File) {
          final mod = await _parseLocalMod(entity);
          if (mod != null) newMods.add(mod);
        }
      }

      newMods.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      _mods = newMods;
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  Future<LocalMod?> _parseLocalMod(File file) async {
    try {
      final stat = await file.stat();
      final fileName = p.basename(file.path);
      
      bool enabled;
      String name;
      
      if (fileName.endsWith('.jar.disabled') || fileName.endsWith('.jar.old')) {
        enabled = false;
        name = fileName.replaceAll('.jar.disabled', '').replaceAll('.jar.old', '');
      } else if (fileName.endsWith('.jar')) {
        enabled = true;
        name = fileName.replaceAll('.jar', '');
      } else if (fileName.endsWith('.litemod')) {
        enabled = true;
        name = fileName.replaceAll('.litemod', '');
      } else {
        return null;
      }

      
      return LocalMod(
        filePath: file.path,
        fileName: fileName,
        name: name,
        enabled: enabled,
        fileSize: stat.size,
        loaderType: ModLoaderType.none, 
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> refresh() async {
    if (_currentVersionId != null) {
      await loadMods(_currentVersionId);
    }
  }

  Future<bool> enableMod(LocalMod mod) async {
    try {
      final file = File(mod.filePath);
      if (!await file.exists()) return false;

      String newPath;
      if (mod.filePath.endsWith('.jar.disabled')) {
        newPath = mod.filePath.replaceAll('.jar.disabled', '.jar');
      } else if (mod.filePath.endsWith('.jar.old')) {
        newPath = mod.filePath.replaceAll('.jar.old', '.jar');
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
      final file = File(mod.filePath);
      if (!await file.exists()) return false;

      final newPath = '${mod.filePath}.disabled';
      if (await File(newPath).exists()) return false;

      await file.rename(newPath);
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleMod(LocalMod mod) async {
    if (mod.enabled) {
      return await disableMod(mod);
    } else {
      return await enableMod(mod);
    }
  }

  Future<bool> deleteMod(LocalMod mod) async {
    try {
      final file = File(mod.filePath);
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

  Future<int> deleteMods(List<LocalMod> mods) async {
    int count = 0;
    for (final mod in mods) {
      if (await deleteMod(mod)) count++;
    }
    return count;
  }

  Future<int> enableMods(List<LocalMod> mods) async {
    int count = 0;
    for (final mod in mods) {
      if (!mod.enabled) {
        if (await enableMod(mod)) count++;
      }
    }
    return count;
  }

  Future<int> disableMods(List<LocalMod> mods) async {
    int count = 0;
    for (final mod in mods) {
      if (mod.enabled) {
        if (await disableMod(mod)) count++;
      }
    }
    return count;
  }

  Future<void> addMod(String filePath, String? versionId) async {
    if (versionId == null) return;
    try {
      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) return;

      final modsDir = Directory(getModsDir(versionId));
      if (!await modsDir.exists()) {
        await modsDir.create(recursive: true);
      }

      final fileName = p.basename(filePath);
      final destPath = p.join(modsDir.path, fileName);

      await sourceFile.copy(destPath);
      await refresh();
    } catch (_) {}
  }

  Future<void> openModsFolder(String? versionId) async {
    if (versionId == null) return;
    
    final modsDir = Directory(getModsDir(versionId));
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
