import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';

enum ResourceType {
  mod,
  resourcePack,
  shaderPack,
  save,
  dataPack, 
}

class ResourceFile {
  final String path;
  final String fileName;
  final String name;
  final bool isEnabled;
  final int size;
  final DateTime modified;
  final bool isDirectory;

  ResourceFile({
    required this.path,
    required this.fileName,
    required this.name,
    required this.isEnabled,
    required this.size,
    required this.modified,
    required this.isDirectory,
  });
}

class ResourceService extends ChangeNotifier {
  List<ResourceFile> _mods = [];
  List<ResourceFile> _resourcePacks = [];
  List<ResourceFile> _shaderPacks = [];
  List<ResourceFile> _saves = [];
  List<ResourceFile> _currentDataPacks = [];
  
  bool _isLoading = false;
  String? _runDirectory;

  List<ResourceFile> get mods => _mods;
  List<ResourceFile> get resourcePacks => _resourcePacks;
  List<ResourceFile> get shaderPacks => _shaderPacks;
  List<ResourceFile> get saves => _saves;
  List<ResourceFile> get currentDataPacks => _currentDataPacks;
  bool get isLoading => _isLoading;
  String? get runDirectory => _runDirectory;

  Future<void> loadResources(String runDirectory) async {
    _runDirectory = runDirectory;
    _isLoading = true;
    notifyListeners();

    try {
      await Future.wait([
        _loadMods(runDirectory),
        _loadResourcePacks(runDirectory),
        _loadShaderPacks(runDirectory),
        _loadSaves(runDirectory),
      ]);
    } catch (e) {
      debugPrint('Failed to load resources: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadDataPacks(String savePath) async {
    _isLoading = true;
    notifyListeners();
    try {
      _currentDataPacks = await _listFiles(p.join(savePath, 'datapacks'), (name) => true);
    } catch (e) {
      debugPrint('Failed to load data packs: $e');
      _currentDataPacks = [];
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadMods(String dir) async {
    _mods = await _listFiles(p.join(dir, 'mods'), (name) {
      if (name.endsWith('.jar') || name.endsWith('.litemod')) return true;
      if (name.endsWith('.jar.disabled') || name.endsWith('.litemod.disabled')) return false; 
      return null; 
    });
  }

  Future<void> _loadResourcePacks(String dir) async {
    _resourcePacks = await _listFiles(p.join(dir, 'resourcepacks'), (name) => true); 
  }

  Future<void> _loadShaderPacks(String dir) async {
    _shaderPacks = await _listFiles(p.join(dir, 'shaderpacks'), (name) => true);
  }

  Future<void> _loadSaves(String dir) async {
    
    _saves = await _listDirectories(p.join(dir, 'saves'));
  }

  Future<List<ResourceFile>> _listFiles(String dirPath, bool? Function(String) isEnabledChecker) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final files = <ResourceFile>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        final stat = await entity.stat();
        final name = p.basename(entity.path);
        final isEnabled = isEnabledChecker(name);
        
        if (isEnabled != null) {
           files.add(ResourceFile(
            path: entity.path,
            fileName: name,
            name: name.replaceAll(RegExp(r'\.disabled$'), ''),
            isEnabled: isEnabled,
            size: stat.size,
            modified: stat.modified,
            isDirectory: false,
          ));
        }
      } else if (entity is Directory) {
         
         final stat = await entity.stat();
         final name = p.basename(entity.path);
         
         if (isEnabledChecker(name) != null) {
            files.add(ResourceFile(
              path: entity.path,
              fileName: name,
              name: name,
              isEnabled: true, 
              size: 0, 
              modified: stat.modified,
              isDirectory: true,
            ));
         }
      }
    }
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return files;
  }

  Future<List<ResourceFile>> _listDirectories(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final files = <ResourceFile>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final stat = await entity.stat();
        final name = p.basename(entity.path);
        files.add(ResourceFile(
          path: entity.path,
          fileName: name,
          name: name,
          isEnabled: true,
          size: 0,
          modified: stat.modified,
          isDirectory: true,
        ));
      }
    }
    files.sort((a, b) => a.modified.compareTo(b.modified) * -1); 
    return files;
  }

  Future<void> toggleResource(ResourceFile resource) async {
    if (resource.isDirectory) return; 
    
    final newPath = resource.isEnabled 
        ? '${resource.path}.disabled'
        : resource.path.replaceAll(RegExp(r'\.disabled$'), '');
    
    try {
      await File(resource.path).rename(newPath);
      await loadResources(_runDirectory!);
    } catch (e) {
      debugPrint('Failed to toggle resource: $e');
    }
  }

  Future<void> deleteResource(ResourceFile resource) async {
    try {
      if (resource.isDirectory) {
        await Directory(resource.path).delete(recursive: true);
      } else {
        await File(resource.path).delete();
      }
      await loadResources(_runDirectory!);
    } catch (e) {
      debugPrint('Failed to delete resource: $e');
    }
  }

  Future<void> importFiles(List<String> filePaths, ResourceType type) async {
    if (_runDirectory == null) return;
    
    String targetDirName;
    switch (type) {
      case ResourceType.mod: targetDirName = 'mods'; break;
      case ResourceType.resourcePack: targetDirName = 'resourcepacks'; break;
      case ResourceType.shaderPack: targetDirName = 'shaderpacks'; break;
      case ResourceType.save: targetDirName = 'saves'; break;
      case ResourceType.dataPack: return; 
    }

    final targetDir = Directory(p.join(_runDirectory!, targetDirName));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    for (final path in filePaths) {
      final sourceFile = File(path);
      final sourceDir = Directory(path);
      final name = p.basename(path);
      final destPath = p.join(targetDir.path, name);

      try {
        if (await sourceFile.exists()) {
           await sourceFile.copy(destPath);
        } else if (await sourceDir.exists()) {
           
           
           await _copyDirectory(sourceDir, Directory(destPath));
        }
      } catch (e) {
        debugPrint('Failed to import $path: $e');
      }
    }
    await loadResources(_runDirectory!);
  }

  Future<void> importDataPacks(List<String> filePaths, String savePath) async {
    final targetDir = Directory(p.join(savePath, 'datapacks'));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    for (final path in filePaths) {
      final sourceFile = File(path);
      final sourceDir = Directory(path);
      final name = p.basename(path);
      final destPath = p.join(targetDir.path, name);

      try {
        if (await sourceFile.exists()) {
           await sourceFile.copy(destPath);
        } else if (await sourceDir.exists()) {
           await _copyDirectory(sourceDir, Directory(destPath));
        }
      } catch (e) {
        debugPrint('Failed to import data pack $path: $e');
      }
    }
    await loadDataPacks(savePath);
  }

  Future<void> toggleDataPack(ResourceFile resource, String savePath) async {
    if (resource.isDirectory) return; 
    
    final newPath = resource.isEnabled 
        ? '${resource.path}.disabled'
        : resource.path.replaceAll(RegExp(r'\.disabled$'), '');
    
    try {
      await File(resource.path).rename(newPath);
      await loadDataPacks(savePath);
    } catch (e) {
      debugPrint('Failed to toggle data pack: $e');
    }
  }

  Future<void> deleteDataPack(ResourceFile resource, String savePath) async {
    try {
      if (resource.isDirectory) {
        await Directory(resource.path).delete(recursive: true);
      } else {
        await File(resource.path).delete();
      }
      await loadDataPacks(savePath);
    } catch (e) {
      debugPrint('Failed to delete data pack: $e');
    }
  }

  Future<void> _unzipSave(String zipPath, Directory targetDir) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      
      bool hasLevelDatAtRoot = false;
      for (final file in archive) {
        if (file.name == 'level.dat' || file.name == 'level.dat_old') {
          hasLevelDatAtRoot = true;
          break;
        }
      }
      
      final extractDir = hasLevelDatAtRoot 
          ? Directory(p.join(targetDir.path, p.basenameWithoutExtension(zipPath)))
          : targetDir;

      if (!await extractDir.exists()) await extractDir.create(recursive: true);

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(p.join(extractDir.path, filename));
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(data);
        }
      }
    } catch (e) {
      debugPrint('Failed to unzip save: $e');
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final newPath = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }
  
  Future<void> openDirectory(ResourceType type) async {
     if (_runDirectory == null) return;
     String targetDirName;
     switch (type) {
      case ResourceType.mod: targetDirName = 'mods'; break;
      case ResourceType.resourcePack: targetDirName = 'resourcepacks'; break;
      case ResourceType.shaderPack: targetDirName = 'shaderpacks'; break;
      case ResourceType.save: targetDirName = 'saves'; break;
      case ResourceType.dataPack: return; 
    }
    final path = p.join(_runDirectory!, targetDirName);
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    
    
    
    if (Platform.isWindows) {
      Process.run('explorer', [path]);
    } else if (Platform.isMacOS) {
      Process.run('open', [path]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [path]);
    }
  }
}
