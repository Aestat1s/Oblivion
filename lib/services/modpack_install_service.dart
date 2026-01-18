import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import '../models/resource_item.dart';
import 'game_service.dart';
import 'download_service.dart';
import 'config_service.dart';

enum ModpackType { modrinth, curseforge, unknown }

class ModpackInfo {
  final ModpackType type;
  final String name;
  final String? version;
  final String? minecraftVersion;
  final String? forgeVersion;
  final String? fabricVersion;
  final String? quiltVersion;
  final String? neoforgeVersion;
  final List<ModpackFile> files;
  final String? overridesPath;

  ModpackInfo({
    required this.type,
    required this.name,
    this.version,
    this.minecraftVersion,
    this.forgeVersion,
    this.fabricVersion,
    this.quiltVersion,
    this.neoforgeVersion,
    this.files = const [],
    this.overridesPath,
  });
}

class ModpackFile {
  final String path;
  final List<String> downloadUrls;
  final int? size;
  final String? sha1;
  final bool required;

  ModpackFile({
    required this.path,
    required this.downloadUrls,
    this.size,
    this.sha1,
    this.required = true,
  });
}

class ModpackInstallService extends ChangeNotifier {
  final GameService _gameService;
  final DownloadService _downloadService;
  final ConfigService _configService;

  bool _isInstalling = false;
  String _status = '';
  double _progress = 0;

  ModpackInstallService(this._gameService, this._downloadService, this._configService);

  bool get isInstalling => _isInstalling;
  String get status => _status;
  double get progress => _progress;

  Future<bool> installFromFile(
    String filePath, {
    String? instanceName,
    void Function(String)? onStatus,
    void Function(double)? onProgress,
  }) async {
    if (_isInstalling) return false;

    _isInstalling = true;
    notifyListeners();

    try {
      return await _installFromFileInternal(
        filePath,
        instanceName: instanceName,
        onStatus: onStatus,
        onProgress: onProgress,
      );
    } finally {
      _isInstalling = false;
      notifyListeners();
    }
  }

  Future<bool> _installFromFileInternal(
    String filePath, {
    String? instanceName,
    void Function(String)? onStatus,
    void Function(double)? onProgress,
  }) async {
    _status = '正在分析整合包...';
    _progress = 0;
    notifyListeners();

    try {
      final file = File(filePath);
      if (!await file.exists()) throw Exception('整合包文件不存在');

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final info = await _analyzeModpack(archive);
      if (info == null) throw Exception('无法识别整合包格式');

      final finalName = instanceName ?? info.name;
      if (finalName.isEmpty) throw Exception('整合包名称无效');

      return await _installModpack(
        archive: archive,
        info: info,
        instanceName: finalName,
        onStatus: onStatus ?? (s) { _status = s; notifyListeners(); },
        onProgress: onProgress ?? (p) { _progress = p; notifyListeners(); },
      );
    } catch (e) {
      _status = '安装失败: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> installFromResource(
    ResourceItem item,
    ResourceVersion version, {
    String? instanceName,
    void Function(String)? onStatus,
    void Function(double)? onProgress,
  }) async {
    if (_isInstalling) return false;
    if (version.files.isEmpty) return false;

    _isInstalling = true;
    _status = '正在下载整合包...';
    _progress = 0;
    notifyListeners();

    try {
      final file = version.files.first;
      final tempDir = Directory.systemTemp;
      final tempPath = p.join(tempDir.path, 'modpack_${DateTime.now().millisecondsSinceEpoch}.mrpack');

      onStatus?.call('正在下载整合包...');

      final response = await http.get(Uri.parse(file.url));
      if (response.statusCode != 200) {
        throw Exception('下载失败: HTTP ${response.statusCode}');
      }

      await File(tempPath).writeAsBytes(response.bodyBytes);
      onProgress?.call(0.1);

      final success = await _installFromFileInternal(
        tempPath,
        instanceName: instanceName ?? item.title,
        onStatus: onStatus,
        onProgress: (p) => onProgress?.call(0.1 + p * 0.9),
      );

      try { await File(tempPath).delete(); } catch (_) {}

      return success;
    } catch (e) {
      _status = '安装失败: $e';
      notifyListeners();
      return false;
    } finally {
      _isInstalling = false;
      notifyListeners();
    }
  }

  Future<ModpackInfo?> _analyzeModpack(Archive archive) async {
    final modrinthIndex = archive.findFile('modrinth.index.json');
    if (modrinthIndex != null) return _parseModrinthPack(modrinthIndex);

    final cfManifest = archive.findFile('manifest.json');
    if (cfManifest != null) return _parseCurseforgePack(cfManifest);

    return null;
  }

  ModpackInfo _parseModrinthPack(ArchiveFile indexFile) {
    final content = utf8.decode(indexFile.content as List<int>);
    final json = jsonDecode(content) as Map<String, dynamic>;

    String? minecraftVersion;
    String? forgeVersion;
    String? fabricVersion;
    String? quiltVersion;
    String? neoforgeVersion;

    final dependencies = json['dependencies'] as Map<String, dynamic>?;
    if (dependencies != null) {
      for (final entry in dependencies.entries) {
        switch (entry.key.toLowerCase()) {
          case 'minecraft':
            minecraftVersion = entry.value.toString();
          case 'forge':
            forgeVersion = entry.value.toString();
          case 'fabric-loader':
            fabricVersion = entry.value.toString();
          case 'quilt-loader':
            quiltVersion = entry.value.toString();
          case 'neoforge':
          case 'neo-forge':
            neoforgeVersion = entry.value.toString();
        }
      }
    }

    final files = <ModpackFile>[];
    final filesList = json['files'] as List?;
    if (filesList != null) {
      for (final file in filesList) {
        final path = file['path'] as String?;
        final downloads = file['downloads'] as List?;
        if (path == null || downloads == null) continue;

        final env = file['env'] as Map<String, dynamic>?;
        final clientEnv = env?['client']?.toString();
        if (clientEnv == 'unsupported') continue;

        files.add(ModpackFile(
          path: path,
          downloadUrls: downloads.map((u) => u.toString()).toList(),
          size: file['fileSize'] as int?,
          sha1: (file['hashes'] as Map<String, dynamic>?)?['sha1']?.toString(),
          required: clientEnv != 'optional',
        ));
      }
    }

    return ModpackInfo(
      type: ModpackType.modrinth,
      name: json['name']?.toString() ?? 'Unknown',
      version: json['versionId']?.toString(),
      minecraftVersion: minecraftVersion,
      forgeVersion: forgeVersion,
      fabricVersion: fabricVersion,
      quiltVersion: quiltVersion,
      neoforgeVersion: neoforgeVersion,
      files: files,
      overridesPath: 'overrides',
    );
  }

  ModpackInfo _parseCurseforgePack(ArchiveFile manifestFile) {
    final content = utf8.decode(manifestFile.content as List<int>);
    final json = jsonDecode(content) as Map<String, dynamic>;

    String? minecraftVersion;
    String? forgeVersion;
    String? fabricVersion;

    final minecraft = json['minecraft'] as Map<String, dynamic>?;
    if (minecraft != null) {
      minecraftVersion = minecraft['version']?.toString();
      
      final modLoaders = minecraft['modLoaders'] as List?;
      if (modLoaders != null) {
        for (final loader in modLoaders) {
          final id = loader['id']?.toString().toLowerCase() ?? '';
          if (id.startsWith('forge-')) {
            forgeVersion = id.replaceFirst('forge-', '');
          } else if (id.startsWith('fabric-')) {
            fabricVersion = id.replaceFirst('fabric-', '');
          }
        }
      }
    }

    final files = <ModpackFile>[];
    final filesList = json['files'] as List?;
    if (filesList != null) {
      for (final file in filesList) {
        final projectId = file['projectID'];
        final fileId = file['fileID'];
        if (projectId == null || fileId == null) continue;

        files.add(ModpackFile(
          path: 'mods/',
          downloadUrls: [],
          required: file['required'] != false,
        ));
      }
    }

    return ModpackInfo(
      type: ModpackType.curseforge,
      name: json['name']?.toString() ?? 'Unknown',
      version: json['version']?.toString(),
      minecraftVersion: minecraftVersion,
      forgeVersion: forgeVersion,
      fabricVersion: fabricVersion,
      files: files,
      overridesPath: json['overrides']?.toString() ?? 'overrides',
    );
  }

  Future<bool> _installModpack({
    required Archive archive,
    required ModpackInfo info,
    required String instanceName,
    required void Function(String) onStatus,
    required void Function(double) onProgress,
  }) async {
    if (info.minecraftVersion == null) {
      throw Exception('整合包未指定 Minecraft 版本');
    }

    final gameDir = _configService.gameDirectory;
    final versionsDir = p.join(gameDir, 'versions');
    final instanceDir = p.join(versionsDir, instanceName);

    if (await Directory(instanceDir).exists()) {
      throw Exception('实例 "$instanceName" 已存在');
    }

    onStatus('正在安装 Minecraft ${info.minecraftVersion}...');
    onProgress(0.1);

    await _gameService.refreshVersions();
    final mcVersion = _gameService.availableVersions.firstWhere(
      (v) => v.id == info.minecraftVersion,
      orElse: () => throw Exception('找不到 Minecraft ${info.minecraftVersion}'),
    );

    await _gameService.installVersion(
      mcVersion,
      customName: instanceName,
      fabric: info.fabricVersion,
      forge: info.forgeVersion,
      quilt: info.quiltVersion,
      onStatus: onStatus,
      onProgress: (p) => onProgress(0.1 + p * 0.3),
    );

    onProgress(0.4);

    if (info.overridesPath != null) {
      onStatus('正在复制整合包文件...');
      await _extractOverrides(archive, info.overridesPath!, instanceDir);
      await _extractOverrides(archive, 'client-overrides', instanceDir);
    }

    onProgress(0.5);

    if (info.files.isNotEmpty) {
      onStatus('正在下载 ${info.files.length} 个文件...');
      
      final downloadFiles = <DownloadFile>[];
      for (final file in info.files) {
        if (file.downloadUrls.isEmpty) continue;
        
        final destPath = p.join(instanceDir, file.path);
        final urls = _addMirrorUrls(file.downloadUrls);
        
        downloadFiles.add(DownloadFile(
          url: urls.first,
          path: destPath,
          sha1: file.sha1,
          size: file.size,
        ));
      }

      if (downloadFiles.isNotEmpty) {
        final success = await _downloadService.downloadFilesInBackground(
          '整合包: $instanceName',
          downloadFiles,
          _configService.settings.concurrentDownloads,
          onProgress: (p) => onProgress(0.5 + p * 0.5),
          onStatus: onStatus,
        );

        if (!success) throw Exception('下载文件失败');
      }
    }

    onProgress(1.0);
    onStatus('安装完成！');

    return true;
  }

  Future<void> _extractOverrides(Archive archive, String overridesPath, String destDir) async {
    final prefix = overridesPath.endsWith('/') ? overridesPath : '$overridesPath/';
    
    for (final file in archive) {
      if (!file.name.startsWith(prefix)) continue;
      if (file.isFile) {
        final relativePath = file.name.substring(prefix.length);
        if (relativePath.isEmpty) continue;
        
        final destPath = p.join(destDir, relativePath);
        final destFile = File(destPath);
        
        await destFile.parent.create(recursive: true);
        await destFile.writeAsBytes(file.content as List<int>);
      }
    }
  }

  List<String> _addMirrorUrls(List<String> urls) {
    final result = <String>[];
    for (final url in urls) {
      if (url.contains('cdn.modrinth.com')) {
        result.add(url.replaceFirst('https://cdn.modrinth.com', 'https://mod.mcimirror.top'));
      }
      if (url.contains('edge.forgecdn.net')) {
        result.add(url.replaceFirst('https://edge.forgecdn.net', 'https://mod.mcimirror.top'));
      }
      result.add(url);
    }
    return result;
  }
}
