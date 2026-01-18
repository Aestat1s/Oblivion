import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import '../models/account.dart';
import '../models/config.dart';
import '../models/game_version.dart';
import '../models/java_info.dart';
import 'config_service.dart';
import 'download_service.dart';
import 'java_service.dart';
import 'analytics_service.dart';

class GameService extends ChangeNotifier {
  final ConfigService _configService;
  final AnalyticsService? _analyticsService;
  final DownloadService _downloadService = DownloadService();
  
  List<GameVersion> _availableVersions = [];
  List<InstalledVersion> _installedVersions = [];
  String? _selectedVersion;
  bool _isLoading = false;
  final String _status = '';
  
  
  Process? _gameProcess;
  bool _isGameRunning = false;
  bool showSnapshots = false;
  bool showOldVersions = false;

  GameService(this._configService, [this._analyticsService]) {
    _loadInstalledVersions();
  }

  List<GameVersion> get availableVersions => _availableVersions;
  List<InstalledVersion> get installedVersions => _installedVersions;
  String? get selectedVersion => _selectedVersion;
  bool get isLoading => _isLoading;
  String get status => _status;
  DownloadService get downloadService => _downloadService;
  bool get isGameRunning => _isGameRunning;

  String get _gameDir => _configService.gameDirectory;
  String get _versionsDir => p.join(_gameDir, 'versions');
  String get _librariesDir => p.join(_gameDir, 'libraries');
  String get _assetsDir => p.join(_gameDir, 'assets');

  
  VersionProfile? getVersionProfile(String versionId) {
    try {
      return _configService.config.versionProfiles.firstWhere((p) => p.versionId == versionId);
    } catch (_) {
      return null;
    }
  }

  
  Future<void> saveVersionProfile(VersionProfile profile) async {
    final profiles = _configService.config.versionProfiles;
    final index = profiles.indexWhere((p) => p.versionId == profile.versionId);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
    await _configService.save();
    notifyListeners();
  }

  Future<void> _loadInstalledVersions() async {
    final newVersions = <InstalledVersion>[];
    final dir = Directory(_versionsDir);
    
    if (!await dir.exists()) {
      _installedVersions = newVersions;
      notifyListeners();
      return;
    }

    final seenIds = <String>{};
    
    
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final versionId = p.basename(entity.path);
        
        if (seenIds.contains(versionId)) continue;
        seenIds.add(versionId);
        
        final jsonFile = File(p.join(entity.path, '$versionId.json'));
        
        
        if (await jsonFile.exists()) {
          try {
            
            final content = await jsonFile.readAsString();
            final json = jsonDecode(content);
            newVersions.add(InstalledVersion.fromJson(json, entity.path));
          } catch (_) {
            
            newVersions.add(InstalledVersion(
              id: versionId,
              type: 'unknown',
              path: entity.path,
            ));
          }
        }
      }
    }

    newVersions.sort((a, b) => b.id.compareTo(a.id));
    _installedVersions = newVersions;
    
    if (_selectedVersion == null && _installedVersions.isNotEmpty) {
      _selectedVersion = _installedVersions.first.id;
    }
    notifyListeners();
  }

  Future<void> refreshVersions() async {
    _isLoading = true;
    notifyListeners();

    try {
      final url = _configService.settings.downloadSource == DownloadSource.bmclapi
          ? 'https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json'
          : 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json';
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final manifest = VersionManifest.fromJson(jsonDecode(response.body));
        _availableVersions = manifest.versions;
      }
    } catch (e) {
      debugPrint('Failed to fetch versions: $e');
    }

    await _loadInstalledVersions();
    _isLoading = false;
    notifyListeners();
  }

  void selectVersion(String versionId) {
    _selectedVersion = versionId;
    _configService.config.selectedVersionId = versionId;
    _configService.save();
    notifyListeners();
  }

  InstalledVersion? getInstalledVersion(String id) {
    try {
      return _installedVersions.firstWhere((v) => v.id == id);
    } catch (_) {
      return null;
    }
  }

  
  Future<void> renameVersion(String versionId, String newName) async {
    final oldDir = Directory(p.join(_versionsDir, versionId));
    final newDir = Directory(p.join(_versionsDir, newName));
    
    if (!await oldDir.exists()) throw Exception('版本不存在');
    if (await newDir.exists()) throw Exception('目标名称已存在');

    
    await oldDir.rename(newDir.path);
    
    
    final oldJson = File(p.join(newDir.path, '$versionId.json'));
    final newJson = File(p.join(newDir.path, '$newName.json'));
    if (await oldJson.exists()) {
      final content = jsonDecode(await oldJson.readAsString());
      content['id'] = newName;
      await newJson.writeAsString(jsonEncode(content));
      await oldJson.delete();
    }

    final oldJar = File(p.join(newDir.path, '$versionId.jar'));
    final newJar = File(p.join(newDir.path, '$newName.jar'));
    if (await oldJar.exists()) {
      await oldJar.rename(newJar.path);
    }

    
    final profile = getVersionProfile(versionId);
    if (profile != null) {
      _configService.config.versionProfiles.removeWhere((p) => p.versionId == versionId);
      await saveVersionProfile(VersionProfile(
        versionId: newName,
        displayName: profile.displayName == versionId ? newName : profile.displayName,
        isolation: profile.isolation,
        javaPath: profile.javaPath,
        minMemory: profile.minMemory,
        maxMemory: profile.maxMemory,
      ));
    }

    if (_selectedVersion == versionId) {
      _selectedVersion = newName;
    }

    await _loadInstalledVersions();
  }

  
  Future<void> deleteVersion(String versionId) async {
    final versionDir = Directory(p.join(_versionsDir, versionId));
    if (!await versionDir.exists()) return;

    if (Platform.isWindows) {
      
      await Process.run('powershell', [
        '-Command',
        'Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory("${versionDir.path}", "OnlyErrorDialogs", "SendToRecycleBin")'
      ]);
    } else {
      await versionDir.delete(recursive: true);
    }

    _configService.config.versionProfiles.removeWhere((p) => p.versionId == versionId);
    await _configService.save();

    if (_selectedVersion == versionId) {
      _selectedVersion = _installedVersions.isNotEmpty ? _installedVersions.first.id : null;
    }

    await _loadInstalledVersions();
  }

  
  Future<String> backupVersion(String versionId, {void Function(String)? onStatus}) async {
    onStatus?.call('正在准备备份...');
    final versionDir = Directory(p.join(_versionsDir, versionId));
    if (!await versionDir.exists()) throw Exception('版本不存在');

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final backupPath = p.join(_gameDir, 'backups', '$versionId-$timestamp.zip');
    await Directory(p.dirname(backupPath)).create(recursive: true);

    onStatus?.call('正在压缩文件...');
    final archive = Archive();
    
    await for (final entity in versionDir.list(recursive: true)) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: versionDir.path);
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
      }
    }

    final zipData = ZipEncoder().encode(archive);
    if (zipData != null) {
      await File(backupPath).writeAsBytes(zipData);
    }

    onStatus?.call('备份完成');
    return backupPath;
  }

  
  Future<void> duplicateVersion(String versionId, String newName) async {
    final sourceDir = Directory(p.join(_versionsDir, versionId));
    final targetDir = Directory(p.join(_versionsDir, newName));
    
    if (!await sourceDir.exists()) throw Exception('源版本不存在');
    if (await targetDir.exists()) throw Exception('目标名称已存在');

    await targetDir.create(recursive: true);

    await for (final entity in sourceDir.list(recursive: true)) {
      final relativePath = p.relative(entity.path, from: sourceDir.path);
      final targetPath = p.join(targetDir.path, relativePath);

      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        String newRelativePath = relativePath;
        
        if (relativePath == '$versionId.json') {
          newRelativePath = '$newName.json';
          final content = jsonDecode(await entity.readAsString());
          content['id'] = newName;
          await File(p.join(targetDir.path, newRelativePath)).writeAsString(jsonEncode(content));
          continue;
        } else if (relativePath == '$versionId.jar') {
          newRelativePath = '$newName.jar';
        }
        await entity.copy(p.join(targetDir.path, newRelativePath));
      }
    }

    await _loadInstalledVersions();
  }

  
  int calculateDynamicMemory() {
    if (!_configService.settings.dynamicMemory) {
      return _configService.settings.maxMemory;
    }

    
    final totalMemoryMB = 16384; 
    final availableMemoryMB = (totalMemoryMB * 0.7).toInt(); 
    
    final maxSetting = _configService.settings.maxMemory;
    return availableMemoryMB.clamp(1024, maxSetting);
  }

  
  String getRunDirectory(String versionId) {
    final profile = getVersionProfile(versionId);
    final isolation = profile?.isolation ?? _configService.settings.defaultIsolation;
    
    switch (isolation) {
      case IsolationType.none:
        return _gameDir;
      case IsolationType.partial:
      case IsolationType.full:
        return p.join(_versionsDir, versionId);
    }
  }

  Future<void> launchGame(
    Account account, {
    void Function(String)? onOutput,
    void Function(String)? onStatusChange,
    JavaService? javaService,
  }) async {
    final version = getInstalledVersion(_selectedVersion ?? '');
    if (version == null) throw Exception('未找到选中的版本');

    onStatusChange?.call('正在准备启动...');
    
    final profile = getVersionProfile(version.id);
    final globalSettings = _configService.settings;

    
    if (globalSettings.autoCompleteFiles) {
      final complete = await verifyAndCompleteFiles(version.id, onStatus: onStatusChange);
      if (!complete) throw Exception('文件补全失败');
    }

    
    final versionJson = await _resolveVersion(version.id);
    
    
    onStatusChange?.call('正在解压原生库...');
    final nativesDir = p.join(version.path, 'natives');
    await _extractNatives(versionJson, nativesDir);

    
    
    final baseVersion = version.inheritsFrom ?? version.id;
    final (minJava, maxJava) = JavaService.getRequiredJavaVersion(baseVersion);
    final mainClass = versionJson['mainClass'] ?? '';
    final isOldForge = mainClass.contains('launchwrapper') || 
                       mainClass.contains('cpw.mods.fml') ||
                       (version.id.contains('forge') && maxJava != null && maxJava <= 8);

    
    
    String? profileJavaPath = profile?.javaPath;
    
    if (profileJavaPath != null && profileJavaPath.isEmpty) {
      profileJavaPath = null;
    }

    String javaPath = profileJavaPath ?? globalSettings.javaPath ?? '';
    int javaMajorVersion = 0; 

    
    if (profileJavaPath == null && javaService != null && globalSettings.autoSelectJava) {
      final selectedJava = javaService.selectJavaForVersion(
        minJava, 
        maxVersion: isOldForge ? 8 : maxJava,
      );
      
      if (selectedJava != null) {
        javaPath = selectedJava.path;
        javaMajorVersion = selectedJava.majorVersion;
        debugPrint('[Launch] 自动选择 Java: ${javaMajorVersion} (${selectedJava.vendor}) for $baseVersion');
      }
    }
    
    if (javaPath.isEmpty) {
      javaPath = 'java';
    }

    String detectedVersionRaw = '';

    
    if (javaMajorVersion == 0) {
       if (javaPath == 'java') {
          try {
             debugPrint('[Launch] 尝试检测系统 Java 版本...');
             final result = await Process.run('java', ['-version'], runInShell: true);
             final output = result.stderr.toString() + result.stdout.toString();
             detectedVersionRaw = output.trim();
             
             final info = JavaInfo.parse(output, 'java');
             if (info != null) {
                javaMajorVersion = info.majorVersion;
                debugPrint('[Launch] 检测到系统 Java 版本: $javaMajorVersion');
             }
          } catch (e) {
             debugPrint('[Launch] 系统 Java 检测失败: $e');
          }
       } else if (await File(javaPath).exists()) {
          final info = await JavaInfo.fromPath(javaPath);
          if (info != null) {
             javaMajorVersion = info.majorVersion;
             detectedVersionRaw = 'Version: ${info.version}';
             debugPrint('[Launch] 检测到 Java 版本: $javaMajorVersion ($javaPath)');
          }
       }
    }
    
    
    

    
    if (isOldForge && javaMajorVersion > 8) {
       throw Exception('此版本 (Forge/Legacy) 需要 Java 8，但检测到 Java $javaMajorVersion ($javaPath)。\n'
           '检测到的版本信息: \n$detectedVersionRaw\n\n'
           'Minecraft 1.12.2 及以下版本的 Forge 不支持高版本 Java。\n'
           '请安装 Java 8 并设置路径，或在设置中开启自动选择 Java (需确保已安装 Java 8)。');
    }
    
    
    final maxMemory = profile?.maxMemory ?? 
        (globalSettings.dynamicMemory ? calculateDynamicMemory() : globalSettings.maxMemory);
    final minMemory = profile?.minMemory ?? globalSettings.minMemory;

    
    final classpath = await _buildClasspath(versionJson);
    
    
    String clientJar;
    final inheritsFrom = versionJson['inheritsFrom'] as String?;
    if (inheritsFrom != null && inheritsFrom.isNotEmpty) {
      
      clientJar = p.join(_versionsDir, inheritsFrom, '$inheritsFrom.jar');
      debugPrint('[Launch] 使用继承版本的 JAR: $clientJar');
    } else {
      
      clientJar = p.join(version.path, '${version.id}.jar');
    }
    
    
    if (!await File(clientJar).exists()) {
      throw Exception('找不到客户端 JAR: $clientJar');
    }
    
    final classpathStr = [...classpath, clientJar].join(Platform.isWindows ? ';' : ':');

    
    final runDir = getRunDirectory(version.id);
    await Directory(runDir).create(recursive: true);

    
    final jvmArgs = <String>[
      '-Xms${minMemory}m',
      '-Xmx${maxMemory}m',
      '-XX:+UseG1GC',
      '-XX:-UseAdaptiveSizePolicy',
      '-XX:-OmitStackTraceInFastThrow',
      '-Dfml.ignoreInvalidMinecraftCertificates=true',
      '-Dfml.ignorePatchDiscrepancies=true',
      '-Dlog4j2.formatMsgNoLookups=true',
      '-Djava.library.path=$nativesDir',
      '-Dminecraft.launcher.brand=Oblivion',
      '-Dminecraft.launcher.version=1.0.0',
      '-Dminecraft.client.jar=$clientJar',
    ];

    
    final assetIndex = versionJson['assetIndex']?['id'] ?? versionJson['assets'] ?? version.id;

    
    final argumentsJvm = versionJson['arguments']?['jvm'] as List?;
    if (argumentsJvm != null) {
      String replaceArg(String arg) {
        return arg
            .replaceAll('\${auth_player_name}', account.username)
            .replaceAll('\${version_name}', version.id)
            .replaceAll('\${game_directory}', runDir)
            .replaceAll('\${assets_root}', _assetsDir)
            .replaceAll('\${assets_index_name}', assetIndex)
            .replaceAll('\${auth_uuid}', account.uuid)
            .replaceAll('\${auth_access_token}', account.accessToken)
            .replaceAll('\${user_properties}', '{}')
            .replaceAll('\${user_type}', account.type == AccountType.microsoft ? 'msa' : 'legacy')
            .replaceAll('\${version_type}', version.type)
            .replaceAll('\${natives_directory}', nativesDir)
            .replaceAll('\${launcher_name}', 'Oblivion')
            .replaceAll('\${launcher_version}', '1.0.0')
            .replaceAll('\${classpath}', classpathStr);
      }

      for (final arg in argumentsJvm) {
        if (arg is String) {
          jvmArgs.add(replaceArg(arg));
        } else if (arg is Map) {
          final rules = arg['rules'] as List?;
          bool allowed = true;
          if (rules != null) {
             allowed = false;
             for (final rule in rules) {
               final action = rule['action'];
               final os = rule['os'];
               if (os == null) {
                 if (action == 'allow') allowed = true;
               } else {
                 final osName = os['name'];
                 if (Platform.isWindows && osName == 'windows') {
                   if (action == 'allow') allowed = true;
                 } else if (Platform.isMacOS && (osName == 'osx' || osName == 'macos')) {
                   if (action == 'allow') allowed = true;
                 } else if (Platform.isLinux && osName == 'linux') {
                   if (action == 'allow') allowed = true;
                 }
               }
             }
          }
          
          if (allowed) {
            final val = arg['value'];
            if (val is String) {
              jvmArgs.add(replaceArg(val));
            } else if (val is List) {
              for (final v in val) {
                jvmArgs.add(replaceArg(v.toString()));
              }
            }
          }
        }
      }
    }

    
    
    if (javaMajorVersion >= 9 && (version.id.contains('forge') || mainClass.toString().contains('cpw.mods.bootstraplauncher'))) {
        final requiredOpens = [
          '--add-opens', 'java.base/java.util.jar=ALL-UNNAMED',
          '--add-opens', 'java.base/java.lang.invoke=ALL-UNNAMED',
          '--add-opens', 'java.base/java.lang.reflect=ALL-UNNAMED',
          '--add-opens', 'java.base/java.io=ALL-UNNAMED',
          '--add-opens', 'java.base/java.nio=ALL-UNNAMED',
          '--add-opens', 'java.base/java.util=ALL-UNNAMED',
          '--add-opens', 'java.base/sun.security.util=ALL-UNNAMED',
         ];

        for (int i = 0; i < requiredOpens.length; i += 2) {
            final key = requiredOpens[i];
            final value = requiredOpens[i+1];
            bool exists = false;
            for (int j = 0; j < jvmArgs.length - 1; j++) {
                if (jvmArgs[j] == key && jvmArgs[j+1] == value) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                jvmArgs.add(key);
                jvmArgs.add(value);
            }
        }
    }

    final extraJvmArgs = profile?.jvmArgs ?? globalSettings.jvmArgs;
    
    
    
    final windowWidth = profile?.windowWidth ?? globalSettings.windowWidth;
    final windowHeight = profile?.windowHeight ?? globalSettings.windowHeight;
    final fullscreen = profile?.fullscreen ?? globalSettings.fullscreen;

    
    final gameArgs = <String>[];
    
    
    final minecraftArguments = versionJson['minecraftArguments'] as String?;
    if (minecraftArguments != null && minecraftArguments.isNotEmpty) {
      
      final args = minecraftArguments.split(' ').where((s) => s.isNotEmpty).toList();
      for (final arg in args) {
        final replaced = arg
            .replaceAll('\${auth_player_name}', account.username)
            .replaceAll('\${version_name}', version.id)
            .replaceAll('\${game_directory}', runDir)
            .replaceAll('\${assets_root}', _assetsDir)
            .replaceAll('\${assets_index_name}', assetIndex)
            .replaceAll('\${auth_uuid}', account.uuid)
            .replaceAll('\${auth_access_token}', account.accessToken)
            .replaceAll('\${user_properties}', '{}')
            .replaceAll('\${user_type}', account.type == AccountType.microsoft ? 'msa' : 'legacy')
            .replaceAll('\${version_type}', version.type);
        gameArgs.add(replaced);
      }
    } else {
      
      gameArgs.addAll([
        '--username', account.username,
        '--version', version.id,
        '--gameDir', runDir,
        '--assetsDir', _assetsDir,
        '--assetIndex', assetIndex,
        '--uuid', account.uuid,
        '--accessToken', account.accessToken,
        '--userType', account.type == AccountType.microsoft ? 'msa' : 'legacy',
        '--versionType', version.type,
      ]);
    }
    
    
    final argumentsGame = versionJson['arguments']?['game'] as List?;
    if (argumentsGame != null) {
      for (final arg in argumentsGame) {
        if (arg is String) {
          
          final replaced = arg
              .replaceAll('\${auth_player_name}', account.username)
              .replaceAll('\${version_name}', version.id)
              .replaceAll('\${game_directory}', runDir)
              .replaceAll('\${assets_root}', _assetsDir)
              .replaceAll('\${assets_index_name}', assetIndex)
              .replaceAll('\${auth_uuid}', account.uuid)
              .replaceAll('\${auth_access_token}', account.accessToken)
              .replaceAll('\${user_properties}', '{}')
              .replaceAll('\${user_type}', account.type == AccountType.microsoft ? 'msa' : 'legacy')
              .replaceAll('\${version_type}', version.type);
          
          if (!gameArgs.contains(replaced)) {
            gameArgs.add(replaced);
          }
        }
        
      }
    }
    
    debugPrint('[Launch] gameArgs after arguments.game: ${gameArgs.join(' ')}');
    onOutput?.call('[Launch] gameArgs after arguments.game: ${gameArgs.join(' ')}\n');

    
    gameArgs.removeWhere((arg) => arg == '--fullscreen' || arg == '--width' || arg == '--height');
    
    final argsToRemove = <int>[];
    for (int i = 0; i < gameArgs.length; i++) {
      if (i > 0 && (gameArgs[i - 1] == '--width' || gameArgs[i - 1] == '--height')) {
        argsToRemove.add(i);
      }
    }
    for (final i in argsToRemove.reversed) {
      gameArgs.removeAt(i);
    }

    
    if (fullscreen) {
      gameArgs.add('--fullscreen');
      debugPrint('[Launch] Added --fullscreen');
      onOutput?.call('[Launch] Added --fullscreen\n');
    } else if (windowWidth > 0 && windowHeight > 0) {
      gameArgs.addAll(['--width', '$windowWidth', '--height', '$windowHeight']);
      debugPrint('[Launch] Added --width and --height');
      onOutput?.call('[Launch] Added --width and --height\n');
    }

    
    final customGameArgs = profile?.gameArgs ?? globalSettings.gameArgs;
    if (customGameArgs.isNotEmpty) {
      final customArgs = customGameArgs.split(' ').where((s) => s.isNotEmpty).toList();
      for (final arg in customArgs) {
        if (!gameArgs.contains(arg)) {
          gameArgs.add(arg);
        }
      }
      debugPrint('[Launch] Added custom game args: $customGameArgs');
      onOutput?.call('[Launch] Added custom game args: $customGameArgs\n');
    }

    
    onStatusChange?.call('正在启动游戏...');
    
    final args = <String>[...jvmArgs, '-cp', classpathStr, mainClass, ...gameArgs];
    
    
    final launchCmd = 'Launch Command:\nJava: $javaPath\nGame Args: ${gameArgs.join(' ')}\n';
    onOutput?.call('\n=== $launchCmd===\n');
    debugPrint('=== Launch Command ===');
    debugPrint('Java: $javaPath');
    debugPrint('Game Args: ${gameArgs.join(' ')}');
    debugPrint('Full Command: $javaPath ${args.join(' ')}');
    debugPrint('======================');

    final process = await Process.start(javaPath, args, workingDirectory: runDir);
    _gameProcess = process;
    _isGameRunning = true;
    notifyListeners();
    
    process.stdout.transform(utf8.decoder).listen((data) => onOutput?.call(data));
    process.stderr.transform(utf8.decoder).listen((data) => onOutput?.call(data));
    
    
    process.exitCode.then((exitCode) {
      _gameProcess = null;
      _isGameRunning = false;
      notifyListeners();
      onOutput?.call('\n[游戏已退出，退出码: $exitCode]\n');
    });

    
    if (profile != null) {
      profile.lastPlayed = DateTime.now();
      await saveVersionProfile(profile);
    }

    _analyticsService?.trackEvent('Launch Game', data: {
      'version': version.id,
      'type': version.type,
      'java_path': javaPath,
      'memory_max': maxMemory,
    });

    onStatusChange?.call('游戏已启动');
  }

  
  void stopGame() {
    if (_gameProcess != null) {
      _gameProcess!.kill();
      _gameProcess = null;
      _isGameRunning = false;
      notifyListeners();
    }
  }

  Future<bool> verifyAndCompleteFiles(String versionId, {
    void Function(String)? onStatus,
    void Function(double)? onProgress,
  }) async {
    onStatus?.call('正在检查游戏文件...');
    final versionDir = p.join(_versionsDir, versionId);
    final jsonFile = File(p.join(versionDir, '$versionId.json'));
    
    if (!await jsonFile.exists()) {
      onStatus?.call('版本文件不存在');
      debugPrint('[VerifyFiles] 版本文件不存在: $jsonFile');
      return false;
    }

    final versionJson = await _resolveVersion(versionId);
    final missingFiles = <DownloadFile>[];

    
    final inheritsFrom = versionJson['inheritsFrom'] as String?;
    final jarVersion = versionJson['jar'] as String? ?? inheritsFrom ?? versionId;
    final clientJarPath = p.join(_versionsDir, jarVersion, '$jarVersion.jar');
    final clientJar = File(clientJarPath);
    
    debugPrint('[VerifyFiles] 检查客户端 JAR: $clientJarPath');
    debugPrint('[VerifyFiles] inheritsFrom=$inheritsFrom, jar=${versionJson['jar']}, jarVersion=$jarVersion');
    
    if (!await clientJar.exists()) {
      debugPrint('[VerifyFiles] 客户端 JAR 不存在，尝试查找下载信息');
      
      Map<String, dynamic> baseJson = versionJson;
      if (inheritsFrom != null) {
        final baseJsonFile = File(p.join(_versionsDir, inheritsFrom, '$inheritsFrom.json'));
        if (await baseJsonFile.exists()) {
          baseJson = jsonDecode(await baseJsonFile.readAsString()) as Map<String, dynamic>;
          debugPrint('[VerifyFiles] 从继承版本读取下载信息: $inheritsFrom');
        } else {
          debugPrint('[VerifyFiles] 警告：继承版本文件不存在: $baseJsonFile');
        }
      }
      
      final downloads = baseJson['downloads'];
      if (downloads?['client'] != null) {
        missingFiles.add(_createDownloadFile(
          url: downloads['client']['url'],
          path: clientJarPath,
          sha1: downloads['client']['sha1'],
          size: downloads['client']['size'],
        ));
        debugPrint('[VerifyFiles] 添加客户端 JAR 到下载列表');
      } else {
        debugPrint('[VerifyFiles] 错误：无法找到客户端下载信息');
        onStatus?.call('错误：找不到客户端 JAR 文件');
        return false;
      }
    } else {
      debugPrint('[VerifyFiles] 客户端 JAR 存在');
    }

    
    onStatus?.call('正在检查库文件...');
    int checkedLibs = 0;
    int missingLibs = 0;
    
    for (final lib in versionJson['libraries'] ?? []) {
      if (!_shouldIncludeLibrary(lib)) continue;
      checkedLibs++;
      
      final downloads = lib['downloads'];
      if (downloads?['artifact'] != null) {
        final artifact = downloads['artifact'];
        final libPath = p.join(_librariesDir, artifact['path']);
        if (!await File(libPath).exists()) {
          missingFiles.add(_createDownloadFile(
            url: artifact['url'],
            path: libPath,
            sha1: artifact['sha1'],
            size: artifact['size'],
          ));
          missingLibs++;
        }
      } else if (lib['natives'] == null) {
        
        
        final name = lib['name'] as String?;
        if (name != null) {
          final libPath = _mavenNameToPath(name);
          if (libPath != null) {
            final fullPath = p.join(_librariesDir, libPath);
            if (!await File(fullPath).exists()) {
              
              String baseUrl = lib['url'] as String? ?? '';
              if (baseUrl.isEmpty) {
                
                if (name.startsWith('net.minecraftforge:')) {
                  baseUrl = 'https://maven.minecraftforge.net/';
                } else if (name.startsWith('net.minecraft:')) {
                  baseUrl = 'https://libraries.minecraft.net/';
                } else if (name.startsWith('org.ow2.asm:') || name.startsWith('cpw.mods:')) {
                  baseUrl = 'https://maven.minecraftforge.net/';
                } else {
                  baseUrl = 'https://repo1.maven.org/maven2/';
                }
              }
              final fullUrl = baseUrl.endsWith('/') ? '$baseUrl$libPath' : '$baseUrl/$libPath';
              
              missingFiles.add(_createDownloadFile(
                url: fullUrl,
                path: fullPath,
              ));
              missingLibs++;
            }
          }
        }
      }

      
      final natives = lib['natives'];
      String? nativeKey;
      if (natives != null) {
        if (Platform.isWindows) {
          nativeKey = natives['windows'];
        } else if (Platform.isMacOS) {
          nativeKey = natives['osx'] ?? natives['macos'];
        } else if (Platform.isLinux) {
          nativeKey = natives['linux'];
        }
      }
      
      if (nativeKey != null) {
        
        nativeKey = nativeKey.replaceAll('\${arch}', '64'); 
        
        final classifiers = downloads?['classifiers'];
        final nativeInfo = classifiers?[nativeKey];
        if (nativeInfo != null) {
          final nativePath = p.join(_librariesDir, nativeInfo['path']);
          if (!await File(nativePath).exists()) {
            missingFiles.add(_createDownloadFile(
              url: nativeInfo['url'],
              path: nativePath,
              sha1: nativeInfo['sha1'],
              size: nativeInfo['size'],
            ));
            missingLibs++;
          }
        } else {
          
          final name = lib['name'] as String?;
          if (name != null) {
             final parts = name.split(':');
             if (parts.length >= 3) {
                final group = parts[0].replaceAll('.', '/');
                final artifact = parts[1];
                final version = parts[2];
                final classifier = nativeKey;
                
                final relativePath = '$group/$artifact/$version/$artifact-$version-$classifier.jar';
                final libPath = p.join(_librariesDir, relativePath);
                
                if (!await File(libPath).exists()) {
                   String baseUrl = lib['url'] as String? ?? '';
                   if (baseUrl.isEmpty) {
                      if (name.startsWith('net.minecraftforge:')) {
                        baseUrl = 'https://maven.minecraftforge.net/';
                      } else if (name.startsWith('net.minecraft:')) {
                        baseUrl = 'https://libraries.minecraft.net/';
                      } else {
                        baseUrl = 'https://repo1.maven.org/maven2/';
                      }
                   }
                   final fullUrl = baseUrl.endsWith('/') ? '$baseUrl$relativePath' : '$baseUrl/$relativePath';
                   
                   final bmclapiUrl = fullUrl
                       .replaceFirst('https://libraries.minecraft.net', 'https://bmclapi2.bangbang93.com/maven')
                       .replaceFirst('https://resources.download.minecraft.net', 'https://bmclapi2.bangbang93.com/assets')
                       .replaceFirst('https://piston-meta.mojang.com', 'https://bmclapi2.bangbang93.com')
                       .replaceFirst('https://piston-data.mojang.com', 'https://bmclapi2.bangbang93.com')
                       .replaceFirst('https://launchermeta.mojang.com', 'https://bmclapi2.bangbang93.com')
                       .replaceFirst('https://maven.minecraftforge.net/', 'https://bmclapi2.bangbang93.com/maven/')
                       .replaceFirst('https://maven.minecraftforge.net', 'https://bmclapi2.bangbang93.com/maven')
                       .replaceFirst('https://repo1.maven.org/maven2/', 'https://bmclapi2.bangbang93.com/maven/')
                       .replaceFirst('https://repo1.maven.org/maven2', 'https://bmclapi2.bangbang93.com/maven');

                   String primaryUrl;
                   List<String> fallbackUrls;

                   if (_configService.settings.downloadSource == DownloadSource.bmclapi) {
                     primaryUrl = bmclapiUrl;
                     fallbackUrls = [fullUrl];
                   } else {
                     primaryUrl = fullUrl;
                     fallbackUrls = [bmclapiUrl];
                   }

                   missingFiles.add(DownloadFile(
                     url: primaryUrl,
                     path: libPath,
                     fallbackUrls: fallbackUrls,
                   ));
                   missingLibs++;
                   debugPrint('[VerifyFiles] 添加缺失库 (natives-maven): $name -> $relativePath');
                }
             }
          }
        }
      }
    }

    debugPrint('[VerifyFiles] 检查完成：共 $checkedLibs 个库，缺失 $missingLibs 个');

    if (missingFiles.isEmpty) {
      onStatus?.call('文件完整');
      debugPrint('[VerifyFiles] 所有文件完整');
      return true;
    }

    onStatus?.call('正在下载 ${missingFiles.length} 个文件...');
    debugPrint('[VerifyFiles] 开始下载 ${missingFiles.length} 个缺失文件');
    
    final result = await _downloadService.downloadFilesInBackground(
      '补全文件: $versionId',
      missingFiles,
      _configService.settings.concurrentDownloads,
      onProgress: onProgress,
      onStatus: onStatus,
    );
    
    debugPrint('[VerifyFiles] 下载结果: $result');
    return result;
  }

  Future<Map<String, dynamic>> _resolveVersion(String versionId) async {
    final jsonFile = File(p.join(_versionsDir, versionId, '$versionId.json'));
    final json = jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
    
    final inheritsFrom = json['inheritsFrom'] as String?;
    if (inheritsFrom == null) return json;

    final parent = await _resolveVersion(inheritsFrom);
    final merged = Map<String, dynamic>.from(parent);
    
    final parentLibs = List<dynamic>.from(parent['libraries'] ?? []);
    final childLibs = List<dynamic>.from(json['libraries'] ?? []);
    merged['libraries'] = [...parentLibs, ...childLibs];
    
    for (final key in json.keys) {
      if (key == 'libraries') continue;

      if (key == 'arguments') {
        final parentArgs = merged['arguments'] as Map<String, dynamic>? ?? {};
        final childArgs = json['arguments'] as Map<String, dynamic>;
        
        final mergedArgs = Map<String, dynamic>.from(parentArgs);
        
        
        if (childArgs['game'] != null) {
          final parentGame = List<dynamic>.from(mergedArgs['game'] ?? []);
          final childGame = List<dynamic>.from(childArgs['game']);
          mergedArgs['game'] = [...parentGame, ...childGame];
        }
        
        
        if (childArgs['jvm'] != null) {
          final parentJvm = List<dynamic>.from(mergedArgs['jvm'] ?? []);
          final childJvm = List<dynamic>.from(childArgs['jvm']);
          mergedArgs['jvm'] = [...parentJvm, ...childJvm];
        }
        
        merged['arguments'] = mergedArgs;
      } else {
        merged[key] = json[key];
      }
    }
    
    
    merged['inheritsFrom'] = inheritsFrom;
    
    return merged;
  }

  Future<List<String>> _buildClasspath(Map<String, dynamic> versionJson) async {
    final libraries = <String>[];

    for (final lib in versionJson['libraries'] ?? []) {
      if (!_shouldIncludeLibrary(lib)) continue;

      final downloads = lib['downloads'];
      if (downloads?['artifact'] != null) {
        final path = downloads['artifact']['path'];
        if (path != null) libraries.add(p.join(_librariesDir, path));
      } else if (lib['natives'] == null) {
        
        
        final name = lib['name'] as String?;
        if (name != null) {
          final libPath = _mavenNameToPath(name);
          if (libPath != null) libraries.add(p.join(_librariesDir, libPath));
        }
      }
    }

    return libraries;
  }

  String? _mavenNameToPath(String name) {
    final parts = name.split(':');
    if (parts.length < 3) return null;
    final group = parts[0].replaceAll('.', '/');
    final artifact = parts[1];
    final version = parts[2];
    final classifier = parts.length > 3 ? '-${parts[3]}' : '';
    return '$group/$artifact/$version/$artifact-$version$classifier.jar';
  }

  bool _shouldIncludeLibrary(Map<String, dynamic> lib) {
    final rules = lib['rules'] as List?;
    if (rules == null) return true;

    bool allowed = false;
    for (final rule in rules) {
      final action = rule['action'];
      final os = rule['os'];

      if (os == null) {
        allowed = action == 'allow';
      } else {
        final osName = os['name'];
        if (Platform.isWindows && osName == 'windows') {
          allowed = action == 'allow';
        } else if (Platform.isMacOS && (osName == 'osx' || osName == 'macos')) {
          allowed = action == 'allow';
        } else if (Platform.isLinux && osName == 'linux') {
          allowed = action == 'allow';
        }
      }
    }
    return allowed;
  }

  Future<void> _extractNatives(Map<String, dynamic> versionJson, String nativesDir) async {
    final dir = Directory(nativesDir);
    if (!await dir.exists()) await dir.create(recursive: true);

    for (final lib in versionJson['libraries'] ?? []) {
      if (!_shouldIncludeLibrary(lib)) continue;
      
      final natives = lib['natives'];
      if (natives == null) continue;
      
      String? nativeKey;
      if (Platform.isWindows) {
        nativeKey = natives['windows'];
      } else if (Platform.isMacOS) {
        nativeKey = natives['osx'] ?? natives['macos'];
      } else if (Platform.isLinux) {
        nativeKey = natives['linux'];
      }
      if (nativeKey == null) continue;
      
      
      nativeKey = nativeKey.replaceAll('\${arch}', '64'); 

      final downloads = lib['downloads'];
      final classifiers = downloads?['classifiers'];
      if (classifiers == null) continue;

      final nativeInfo = classifiers[nativeKey];
      if (nativeInfo == null) continue;

      final nativePath = p.join(_librariesDir, nativeInfo['path']);
      final nativeFile = File(nativePath);
      
      if (await nativeFile.exists()) {
        try {
          final bytes = await nativeFile.readAsBytes();
          final archive = ZipDecoder().decodeBytes(bytes);
          
          for (final file in archive) {
            if (file.isFile && !file.name.endsWith('.git') && !file.name.endsWith('.sha1') && !file.name.startsWith('META-INF')) {
              final outFile = File(p.join(nativesDir, file.name));
              await outFile.parent.create(recursive: true);
              await outFile.writeAsBytes(file.content as List<int>);
            }
          }
        } catch (e) {
          debugPrint('Failed to extract native: $e');
        }
      }
    }
  }

  String _toBmclapiUrl(String url) {
    return url
        .replaceFirst('https://libraries.minecraft.net', 'https://bmclapi2.bangbang93.com/maven')
        .replaceFirst('https://resources.download.minecraft.net', 'https://bmclapi2.bangbang93.com/assets')
        .replaceFirst('https://piston-meta.mojang.com', 'https://bmclapi2.bangbang93.com')
        .replaceFirst('https://piston-data.mojang.com', 'https://bmclapi2.bangbang93.com')
        .replaceFirst('https://launchermeta.mojang.com', 'https://bmclapi2.bangbang93.com')
        .replaceFirst('https://maven.minecraftforge.net/', 'https://bmclapi2.bangbang93.com/maven/')
        .replaceFirst('https://maven.minecraftforge.net', 'https://bmclapi2.bangbang93.com/maven')
        .replaceFirst('https://repo1.maven.org/maven2/', 'https://bmclapi2.bangbang93.com/maven/')
        .replaceFirst('https://repo1.maven.org/maven2', 'https://bmclapi2.bangbang93.com/maven');
  }

  DownloadFile _createDownloadFile({
    required String url,
    required String path,
    String? sha1,
    int? size,
  }) {
    final bmclapiUrl = _toBmclapiUrl(url);
    String primaryUrl;
    List<String> fallbackUrls;

    if (_configService.settings.downloadSource == DownloadSource.bmclapi) {
      primaryUrl = bmclapiUrl;
      fallbackUrls = [url];
    } else {
      primaryUrl = url;
      fallbackUrls = [bmclapiUrl];
    }

    return DownloadFile(
      url: primaryUrl,
      path: path,
      fallbackUrls: fallbackUrls,
      sha1: sha1,
      size: size,
    );
  }

  String _getMirrorUrl(String url) {
    if (_configService.settings.downloadSource == DownloadSource.bmclapi) {
      return _toBmclapiUrl(url);
    }
    return url;
  }

  
  Future<void> installVersion(
    GameVersion version, {
    String? customName,
    String? fabric,
    String? forge,
    String? quilt,
    String? optifine,
    IsolationType? isolation,
    void Function(String)? onStatus,
    void Function(double)? onProgress,
  }) async {
    
    final vanillaVersionId = version.id;
    final vanillaVersionDir = p.join(_versionsDir, vanillaVersionId);
    
    onStatus?.call('正在获取版本信息...');
    
    
    final response = await http.get(Uri.parse(_getMirrorUrl(version.url)));
    if (response.statusCode != 200) throw Exception('获取版本信息失败');
    
    final versionJson = jsonDecode(response.body) as Map<String, dynamic>;
    
    
    await Directory(vanillaVersionDir).create(recursive: true);
    await File(p.join(vanillaVersionDir, '$vanillaVersionId.json')).writeAsString(jsonEncode(versionJson));

    
    final files = <DownloadFile>[];

    
    final clientDownload = versionJson['downloads']?['client'];
    if (clientDownload != null) {
      files.add(_createDownloadFile(
        url: clientDownload['url'],
        path: p.join(vanillaVersionDir, '$vanillaVersionId.jar'),
        sha1: clientDownload['sha1'],
        size: clientDownload['size'],
      ));
    }

    
    onStatus?.call('正在分析依赖库...');
    for (final lib in versionJson['libraries'] ?? []) {
      if (!_shouldIncludeLibrary(lib)) continue;
      
      final downloads = lib['downloads'];
      if (downloads?['artifact'] != null) {
        final artifact = downloads['artifact'];
        files.add(_createDownloadFile(
          url: artifact['url'],
          path: p.join(_librariesDir, artifact['path']),
          sha1: artifact['sha1'],
          size: artifact['size'],
        ));
      }

      final natives = lib['natives'];
      String? nativeKey;
      if (natives != null) {
        if (Platform.isWindows) {
          nativeKey = natives['windows'];
        } else if (Platform.isMacOS) {
          nativeKey = natives['osx'] ?? natives['macos'];
        } else if (Platform.isLinux) {
          nativeKey = natives['linux'];
        }
      }

      if (nativeKey != null) {
        nativeKey = nativeKey.replaceAll('\${arch}', '64');
        final classifiers = downloads?['classifiers'];
        final nativeInfo = classifiers?[nativeKey];
        if (nativeInfo != null) {
          files.add(_createDownloadFile(
            url: nativeInfo['url'],
            path: p.join(_librariesDir, nativeInfo['path']),
            sha1: nativeInfo['sha1'],
            size: nativeInfo['size'],
          ));
        }
      }
    }

    
    final assetIndex = versionJson['assetIndex'];
    if (assetIndex != null) {
      files.add(_createDownloadFile(
        url: assetIndex['url'],
        path: p.join(_assetsDir, 'indexes', '${assetIndex['id']}.json'),
        sha1: assetIndex['sha1'],
        size: assetIndex['size'],
      ));
    }

    
    onStatus?.call('正在下载 ${files.length} 个文件...');
    final success = await _downloadService.downloadFilesInBackground(
      '版本: $vanillaVersionId',
      files, _configService.settings.concurrentDownloads,
      onProgress: onProgress, onStatus: onStatus,
    );
    if (!success) throw Exception('下载文件失败');

    
    await _downloadAssets(versionJson, onStatus: onStatus, onProgress: onProgress);

    
    String finalVersionId = customName ?? vanillaVersionId;
    Map<String, dynamic>? forgeJson;
    Map<String, dynamic>? optifineJson;
    
    debugPrint('[Install] ModLoader 参数: fabric=$fabric, forge=$forge, quilt=$quilt, optifine=$optifine');
    
    
    if (fabric != null && fabric.isNotEmpty) {
      debugPrint('[Install] 开始安装 Fabric: $fabric');
      finalVersionId = await _installFabric(vanillaVersionId, fabric, customName: customName, onStatus: onStatus);
      debugPrint('[Install] Fabric 安装完成: $finalVersionId');
    } else if (forge != null && forge.isNotEmpty) {
      debugPrint('[Install] 开始安装 Forge: $forge');
      final result = await _installForgeAndGetJson(vanillaVersionId, forge, onStatus: onStatus);
      forgeJson = result.json;
      finalVersionId = customName ?? result.defaultId;
      debugPrint('[Install] Forge 安装完成: $finalVersionId');
    } else if (quilt != null && quilt.isNotEmpty) {
      debugPrint('[Install] 开始安装 Quilt: $quilt');
      finalVersionId = await _installQuilt(vanillaVersionId, quilt, customName: customName, onStatus: onStatus);
      debugPrint('[Install] Quilt 安装完成: $finalVersionId');
    }
    
    
    if (optifine != null && optifine.isNotEmpty) {
      
      if (fabric != null || quilt != null) {
        debugPrint('[Install] OptiFine 与 Fabric/Quilt 不兼容，跳过');
      } else {
        debugPrint('[Install] 开始安装 OptiFine: $optifine');
        optifineJson = await _installOptiFineAndGetJson(vanillaVersionId, optifine, onStatus: onStatus);
        debugPrint('[Install] OptiFine 安装完成');
      }
    }
    
    
    if (forgeJson != null || optifineJson != null) {
      await _createMergedVersion(
        finalVersionId: finalVersionId,
        vanillaVersionId: vanillaVersionId,
        versionType: version.type,
        forgeJson: forgeJson,
        optifineJson: optifineJson,
        onStatus: onStatus,
      );
    } else if (customName != null && customName != vanillaVersionId && fabric == null && quilt == null) {
      debugPrint('[Install] 创建自定义版本: $customName');
      
      final customVersionDir = p.join(_versionsDir, customName);
      await Directory(customVersionDir).create(recursive: true);
      final customJson = {
        'id': customName,
        'inheritsFrom': vanillaVersionId,
        'type': version.type,
      };
      await File(p.join(customVersionDir, '$customName.json')).writeAsString(jsonEncode(customJson));
      finalVersionId = customName;
    } else {
      debugPrint('[Install] 无 ModLoader，使用原版: $vanillaVersionId');
      finalVersionId = vanillaVersionId;
    }

    
    await saveVersionProfile(VersionProfile(
      versionId: finalVersionId,
      displayName: customName ?? finalVersionId,
      isolation: isolation ?? _configService.settings.defaultIsolation,
    ));

    await _loadInstalledVersions();
    onStatus?.call('安装完成！');
  }
  
  
  
  Future<void> _createMergedVersion({
    required String finalVersionId,
    required String vanillaVersionId,
    required String versionType,
    Map<String, dynamic>? forgeJson,
    Map<String, dynamic>? optifineJson,
    void Function(String)? onStatus,
  }) async {
    onStatus?.call('正在合并版本配置...');
    
    final versionDir = p.join(_versionsDir, finalVersionId);
    await Directory(versionDir).create(recursive: true);
    
    
    final vanillaJsonPath = p.join(_versionsDir, vanillaVersionId, '$vanillaVersionId.json');
    final vanillaJsonStr = await File(vanillaJsonPath).readAsString();
    final vanillaJson = jsonDecode(vanillaJsonStr) as Map<String, dynamic>;
    
    
    final mergedJson = Map<String, dynamic>.from(vanillaJson);
    
    
    final libraries = <Map<String, dynamic>>[];
    libraries.addAll((vanillaJson['libraries'] as List?)?.cast<Map<String, dynamic>>() ?? []);
    
    
    if (forgeJson != null) {
      debugPrint('[MergeJson] 合并 Forge JSON');
      
      
      if (forgeJson['mainClass'] != null) {
        mergedJson['mainClass'] = forgeJson['mainClass'];
      }
      
      
      if (forgeJson['minecraftArguments'] != null) {
        mergedJson['minecraftArguments'] = forgeJson['minecraftArguments'];
      }
      
      
      if (forgeJson['arguments'] != null) {
        final forgeArgs = forgeJson['arguments'] as Map<String, dynamic>;
        final mergedArgs = Map<String, dynamic>.from(mergedJson['arguments'] as Map<String, dynamic>? ?? {});
        
        if (forgeArgs['game'] != null) {
          mergedArgs['game'] = List<dynamic>.from(forgeArgs['game'] as List);
        }
        if (forgeArgs['jvm'] != null) {
          mergedArgs['jvm'] = List<dynamic>.from(forgeArgs['jvm'] as List);
        }
        mergedJson['arguments'] = mergedArgs;
      }
      
      
      libraries.addAll((forgeJson['libraries'] as List?)?.cast<Map<String, dynamic>>() ?? []);
    }
    
    
    if (optifineJson != null) {
      debugPrint('[MergeJson] 合并 OptiFine JSON');
      
      
      libraries.addAll((optifineJson['libraries'] as List?)?.cast<Map<String, dynamic>>() ?? []);
      
      
      if (optifineJson['arguments'] != null) {
        final optifineArgs = optifineJson['arguments'] as Map<String, dynamic>;
        if (optifineArgs['game'] != null) {
          final mergedArgs = Map<String, dynamic>.from(mergedJson['arguments'] as Map<String, dynamic>? ?? {});
          final gameArgs = List<dynamic>.from(mergedArgs['game'] ?? []);
          gameArgs.addAll(optifineArgs['game'] as List);
          mergedArgs['game'] = gameArgs;
          mergedJson['arguments'] = mergedArgs;
        }
      }
    }
    
    
    final uniqueLibraries = _deduplicateLibraries(libraries);
    mergedJson['libraries'] = uniqueLibraries;
    
    
    if (forgeJson != null && optifineJson != null) {
      _maintainTweakClassOrder(mergedJson, hasForge: true, hasOptiFine: true);
    } else if (optifineJson != null) {
      _maintainTweakClassOrder(mergedJson, hasForge: false, hasOptiFine: true);
    }
    
    
    mergedJson['id'] = finalVersionId;
    mergedJson.remove('inheritsFrom');
    mergedJson.remove('jar');
    mergedJson.remove('_comment_');
    mergedJson.remove('releaseTime');
    mergedJson.remove('time');
    
    
    await File(p.join(versionDir, '$finalVersionId.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(mergedJson)
    );
    debugPrint('[MergeJson] 已保存合并版本 JSON: $versionDir/$finalVersionId.json');
    
    
    final vanillaJar = p.join(_versionsDir, vanillaVersionId, '$vanillaVersionId.jar');
    final outputJar = p.join(versionDir, '$finalVersionId.jar');
    
    debugPrint('[MergeJson] 检查 JAR 文件：');
    debugPrint('[MergeJson]   原版 JAR: $vanillaJar');
    debugPrint('[MergeJson]   输出 JAR: $outputJar');
    debugPrint('[MergeJson]   原版 JAR 存在: ${await File(vanillaJar).exists()}');
    debugPrint('[MergeJson]   输出 JAR 存在: ${await File(outputJar).exists()}');
    
    if (vanillaJar != outputJar) {
      if (await File(vanillaJar).exists()) {
        if (!await File(outputJar).exists()) {
          onStatus?.call('正在复制游戏文件...');
          await File(vanillaJar).copy(outputJar);
          debugPrint('[MergeJson] 已复制原版 JAR: $vanillaJar -> $outputJar');
        } else {
          debugPrint('[MergeJson] 输出 JAR 已存在，跳过复制');
        }
      } else {
        debugPrint('[MergeJson] 错误：原版 JAR 不存在！');
        throw Exception('原版 JAR 文件不存在: $vanillaJar');
      }
    } else {
      debugPrint('[MergeJson] 原版 JAR 和输出 JAR 路径相同，无需复制');
    }
  }
  
  
  List<Map<String, dynamic>> _deduplicateLibraries(List<Map<String, dynamic>> libraries) {
    final result = <Map<String, dynamic>>[];
    final libraryMap = <String, List<int>>{}; 
    
    for (int i = 0; i < libraries.length; i++) {
      final lib = libraries[i];
      final name = lib['name'] as String?;
      if (name == null) {
        result.add(lib);
        continue;
      }
      
      
      final parts = name.split(':');
      if (parts.length < 3) {
        result.add(lib);
        continue;
      }
      
      final groupId = parts[0];
      final artifactId = parts[1];
      final version = parts[2];
      final key = '$groupId:$artifactId';
      
      if (!libraryMap.containsKey(key)) {
        libraryMap[key] = [result.length];
        result.add(lib);
      } else {
        
        bool isDuplicate = false;
        for (final existingIndex in libraryMap[key]!) {
          final existing = result[existingIndex];
          final existingName = existing['name'] as String;
          final existingParts = existingName.split(':');
          final existingVersion = existingParts[2];
          
          
          final versionComparison = _compareVersions(version, existingVersion);
          
          if (versionComparison > 0) {
            
            result[existingIndex] = lib;
            isDuplicate = true;
            break;
          } else if (versionComparison == 0) {
            
            if (jsonEncode(lib) == jsonEncode(existing)) {
              isDuplicate = true;
              break;
            }
          } else {
            
            isDuplicate = true;
            break;
          }
        }
        
        if (!isDuplicate) {
          libraryMap[key]!.add(result.length);
          result.add(lib);
        }
      }
    }
    
    debugPrint('[Deduplicate] 去重前: ${libraries.length} 个库，去重后: ${result.length} 个库');
    return result;
  }
  
  
  int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map((p) => int.tryParse(p.split('-')[0]) ?? 0).toList();
    final parts2 = v2.split('.').map((p) => int.tryParse(p.split('-')[0]) ?? 0).toList();
    
    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (int i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 != p2) return p1.compareTo(p2);
    }
    return 0;
  }
  
  
  void _maintainTweakClassOrder(Map<String, dynamic> json, {required bool hasForge, required bool hasOptiFine}) {
    
    final minecraftArgs = json['minecraftArguments'] as String?;
    if (minecraftArgs != null) {
      final args = minecraftArgs.split(' ').where((s) => s.isNotEmpty).toList();
      final newArgs = <String>[];
      final tweakClasses = <String>[];
      
      
      for (int i = 0; i < args.length; i++) {
        if (args[i] == '--tweakClass' && i + 1 < args.length) {
          tweakClasses.add(args[i + 1]);
          i++; 
        } else {
          newArgs.add(args[i]);
        }
      }
      
      
      
      final orderedTweakClasses = <String>[];
      
      
      if (hasForge) {
        for (final tweakClass in tweakClasses) {
          if (tweakClass.contains('fml.common.launcher.FMLTweaker') || 
              tweakClass.contains('cpw.mods.fml.common.launcher.FMLTweaker')) {
            orderedTweakClasses.add(tweakClass);
          }
        }
      }
      
      
      if (hasOptiFine) {
        for (final tweakClass in tweakClasses) {
          if (tweakClass.contains('optifine.OptiFineTweaker') || 
              tweakClass.contains('optifine.OptiFineForgeTweaker')) {
            
            if (hasForge && tweakClass.contains('OptiFineTweaker') && !tweakClass.contains('Forge')) {
              
              continue;
            }
            if (!orderedTweakClasses.contains(tweakClass)) {
              orderedTweakClasses.add(tweakClass);
            }
          }
        }
      }
      
      
      for (final tweakClass in orderedTweakClasses) {
        newArgs.add('--tweakClass');
        newArgs.add(tweakClass);
      }
      
      json['minecraftArguments'] = newArgs.join(' ');
      debugPrint('[MaintainTweakClass] 重新排序 TweakClass: $orderedTweakClasses');
    }
    
    
    final arguments = json['arguments'] as Map<String, dynamic>?;
    if (arguments != null && arguments['game'] != null) {
      final gameArgs = List<dynamic>.from(arguments['game'] as List);
      final newArgs = <dynamic>[];
      final tweakClasses = <String>[];
      
      
      for (int i = 0; i < gameArgs.length; i++) {
        if (gameArgs[i] == '--tweakClass' && i + 1 < gameArgs.length) {
          if (gameArgs[i + 1] is String) {
            tweakClasses.add(gameArgs[i + 1] as String);
            i++; 
          }
        } else {
          newArgs.add(gameArgs[i]);
        }
      }
      
      
      final orderedTweakClasses = <String>[];
      
      
      if (hasForge) {
        for (final tweakClass in tweakClasses) {
          if (tweakClass.contains('fml.common.launcher.FMLTweaker') || 
              tweakClass.contains('cpw.mods.fml.common.launcher.FMLTweaker')) {
            orderedTweakClasses.add(tweakClass);
          }
        }
      }
      
      
      if (hasOptiFine) {
        for (final tweakClass in tweakClasses) {
          if (tweakClass.contains('optifine.OptiFineTweaker') || 
              tweakClass.contains('optifine.OptiFineForgeTweaker')) {
            if (hasForge && tweakClass.contains('OptiFineTweaker') && !tweakClass.contains('Forge')) {
              continue;
            }
            if (!orderedTweakClasses.contains(tweakClass)) {
              orderedTweakClasses.add(tweakClass);
            }
          }
        }
      }
      
      
      for (final tweakClass in orderedTweakClasses) {
        newArgs.add('--tweakClass');
        newArgs.add(tweakClass);
      }
      
      arguments['game'] = newArgs;
      debugPrint('[MaintainTweakClass] 重新排序 TweakClass (arguments): $orderedTweakClasses');
    }
  }

  Future<void> _downloadAssets(
    Map<String, dynamic> versionJson, {
    void Function(String)? onStatus,
    void Function(double)? onProgress,
  }) async {
    final assetIndex = versionJson['assetIndex'];
    if (assetIndex == null) return;

    final indexPath = p.join(_assetsDir, 'indexes', '${assetIndex['id']}.json');
    final indexFile = File(indexPath);
    if (!await indexFile.exists()) return;

    onStatus?.call('正在分析资源文件...');
    final indexJson = jsonDecode(await indexFile.readAsString());
    final objects = indexJson['objects'] as Map<String, dynamic>?;
    if (objects == null) return;

    final files = <DownloadFile>[];
    for (final entry in objects.entries) {
      final hash = entry.value['hash'] as String;
      final prefix = hash.substring(0, 2);
      final assetPath = p.join(_assetsDir, 'objects', prefix, hash);
      
      if (!await File(assetPath).exists()) {
        files.add(_createDownloadFile(
          url: 'https://resources.download.minecraft.net/$prefix/$hash',
          path: assetPath,
          sha1: hash,
          size: entry.value['size'],
        ));
      }
    }

    if (files.isNotEmpty) {
      onStatus?.call('正在下载 ${files.length} 个资源文件...');
      await _downloadService.downloadFilesInBackground(
        '资源文件',
        files, _configService.settings.concurrentDownloads,
        onProgress: onProgress, onStatus: onStatus,
      );
    }
  }

  
  Future<List<ModLoaderVersion>> getFabricVersions(String gameVersion) async {
    try {
      final response = await http.get(Uri.parse('https://meta.fabricmc.net/v2/versions/loader/$gameVersion'));
      if (response.statusCode != 200) return [];
      
      final list = jsonDecode(response.body) as List;
      return list.map((e) => ModLoaderVersion(
        version: e['loader']['version'],
        gameVersion: gameVersion,
        type: ModLoaderType.fabric,
        stable: e['loader']['stable'] ?? true,
      )).toList();
    } catch (e) {
      debugPrint('Failed to get Fabric versions: $e');
      return [];
    }
  }

  
  Future<List<ModLoaderVersion>> getForgeVersions(String gameVersion) async {
    try {
      final response = await http.get(Uri.parse('https://bmclapi2.bangbang93.com/forge/minecraft/$gameVersion'));
      if (response.statusCode != 200) return [];
      
      final list = jsonDecode(response.body) as List;
      return list.map((e) => ModLoaderVersion(
        version: e['version'],
        gameVersion: gameVersion,
        type: ModLoaderType.forge,
        stable: e['type'] == 'recommended',
        buildNumber: e['build'],
      )).toList();
    } catch (e) {
      debugPrint('Failed to get Forge versions: $e');
      return [];
    }
  }

  
  Future<List<ModLoaderVersion>> getQuiltVersions(String gameVersion) async {
    try {
      final response = await http.get(Uri.parse('https://meta.quiltmc.org/v3/versions/loader/$gameVersion'));
      if (response.statusCode != 200) return [];
      
      final list = jsonDecode(response.body) as List;
      return list.map((e) => ModLoaderVersion(
        version: e['loader']['version'],
        gameVersion: gameVersion,
        type: ModLoaderType.quilt,
        stable: true,
      )).toList();
    } catch (e) {
      debugPrint('Failed to get Quilt versions: $e');
      return [];
    }
  }

  
  Future<List<ModLoaderVersion>> getOptiFineVersions(String gameVersion) async {
    try {
      final response = await http.get(Uri.parse('https://bmclapi2.bangbang93.com/optifine/$gameVersion'));
      if (response.statusCode != 200) return [];
      
      final list = jsonDecode(response.body) as List;
      return list.map((e) {
        final type = e['type'] as String; 
        final patch = e['patch'] as String; 
        
        return ModLoaderVersion(
          version: '${type}_$patch',
          gameVersion: gameVersion,
          type: ModLoaderType.optiFine,
          stable: type == 'HD_U', 
        );
      }).toList();
    } catch (e) {
      debugPrint('Failed to get OptiFine versions: $e');
      return [];
    }
  }

  Future<String> _installFabric(String gameVersion, String loaderVersion, {
    String? customName,
    void Function(String)? onStatus,
  }) async {
    onStatus?.call('正在安装 Fabric $loaderVersion...');
    
    final response = await http.get(Uri.parse(
      'https://meta.fabricmc.net/v2/versions/loader/$gameVersion/$loaderVersion/profile/json'
    ));
    
    if (response.statusCode != 200) throw Exception('获取 Fabric 配置失败');
    
    final fabricJson = jsonDecode(response.body) as Map<String, dynamic>;
    final defaultId = '$gameVersion-fabric-$loaderVersion';
    final newVersionId = customName ?? defaultId;
    final versionDir = p.join(_versionsDir, newVersionId);
    
    await Directory(versionDir).create(recursive: true);
    
    fabricJson['id'] = newVersionId;
    fabricJson['inheritsFrom'] = gameVersion;
    
    await File(p.join(versionDir, '$newVersionId.json')).writeAsString(jsonEncode(fabricJson));

    
    final files = <DownloadFile>[];
    for (final lib in fabricJson['libraries'] ?? []) {
      final name = lib['name'] as String;
      final url = lib['url'] as String? ?? 'https://maven.fabricmc.net/';
      final path = _mavenNameToPath(name);
      if (path != null) {
        final fullUrl = url.endsWith('/') ? '$url$path' : '$url/$path';
        files.add(DownloadFile(url: fullUrl, path: p.join(_librariesDir, path)));
      }
    }

    if (files.isNotEmpty) {
      onStatus?.call('正在下载 Fabric 库文件...');
      await _downloadService.downloadFilesInBackground(
        'Fabric 库文件',
        files, _configService.settings.concurrentDownloads,
      );
    }

    return newVersionId;
  }



  Future<String> _installQuilt(String gameVersion, String loaderVersion, {
    String? customName,
    void Function(String)? onStatus,
  }) async {
    onStatus?.call('正在安装 Quilt $loaderVersion...');
    
    final response = await http.get(Uri.parse(
      'https://meta.quiltmc.org/v3/versions/loader/$gameVersion/$loaderVersion/profile/json'
    ));
    
    if (response.statusCode != 200) throw Exception('获取 Quilt 配置失败');
    
    final quiltJson = jsonDecode(response.body) as Map<String, dynamic>;
    final defaultId = '$gameVersion-quilt-$loaderVersion';
    final newVersionId = customName ?? defaultId;
    final versionDir = p.join(_versionsDir, newVersionId);
    
    await Directory(versionDir).create(recursive: true);
    
    quiltJson['id'] = newVersionId;
    quiltJson['inheritsFrom'] = gameVersion;
    
    await File(p.join(versionDir, '$newVersionId.json')).writeAsString(jsonEncode(quiltJson));

    
    final files = <DownloadFile>[];
    for (final lib in quiltJson['libraries'] ?? []) {
      final name = lib['name'] as String;
      final url = lib['url'] as String? ?? 'https://maven.quiltmc.org/repository/release/';
      final path = _mavenNameToPath(name);
      if (path != null) {
        final fullUrl = url.endsWith('/') ? '$url$path' : '$url/$path';
        files.add(DownloadFile(url: fullUrl, path: p.join(_librariesDir, path)));
      }
    }

    if (files.isNotEmpty) {
      onStatus?.call('正在下载 Quilt 库文件...');
      await _downloadService.downloadFilesInBackground(
        'Quilt 库文件',
        files, _configService.settings.concurrentDownloads,
      );
    }

    return newVersionId;
  }

  Future<_ForgeInstallResult> _installForgeAndGetJson(String gameVersion, String forgeVersion, {
    void Function(String)? onStatus,
  }) async {
    onStatus?.call('正在准备 Forge $forgeVersion...');
    debugPrint('[Forge] 开始安装 Forge: gameVersion=$gameVersion, forgeVersion=$forgeVersion');
    
    
    final infoResponse = await http.get(Uri.parse(
      'https://bmclapi2.bangbang93.com/forge/minecraft/$gameVersion'
    ));
    if (infoResponse.statusCode != 200) {
      debugPrint('[Forge] 获取 Forge 列表失败: ${infoResponse.statusCode}');
      throw Exception('获取 Forge 信息失败');
    }
    
    final forgeList = jsonDecode(infoResponse.body) as List;
    debugPrint('[Forge] 获取到 ${forgeList.length} 个 Forge 版本');
    
    final forgeInfo = forgeList.firstWhere(
      (f) => f['version'] == forgeVersion,
      orElse: () => null,
    );
    
    if (forgeInfo == null) {
      debugPrint('[Forge] 未找到 Forge 版本: $forgeVersion');
      throw Exception('未找到 Forge 版本: $forgeVersion');
    }
    
    final build = forgeInfo['build'];
    debugPrint('[Forge] 找到 Forge build: $build');
    
    final defaultId = '$gameVersion-forge-$forgeVersion';
    
    
    onStatus?.call('正在下载 Forge 安装器...');
    final installerUrl = 'https://bmclapi2.bangbang93.com/forge/download/$build';
    debugPrint('[Forge] 下载安装器: $installerUrl');
    
    final tempDir = await Directory.systemTemp.createTemp('forge_');
    final installerPath = p.join(tempDir.path, 'installer.jar');
    
    final downloadSuccess = await _downloadService.downloadFilesInBackground(
      'Forge 安装器',
      [DownloadFile(url: installerUrl, path: installerPath)],
      1,
    );
    
    if (!downloadSuccess) {
      debugPrint('[Forge] 安装器下载失败');
      throw Exception('Forge 安装器下载失败');
    }

    final installerFile = File(installerPath);
    if (!await installerFile.exists()) {
      debugPrint('[Forge] 安装器文件不存在: $installerPath');
      throw Exception('Forge 安装器下载失败');
    }
    
    final fileSize = await installerFile.length();
    debugPrint('[Forge] 安装器大小: $fileSize bytes');

    
    onStatus?.call('正在解析 Forge 安装器...');
    final bytes = await installerFile.readAsBytes();
    
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
      debugPrint('[Forge] ZIP 解压成功，包含 ${archive.length} 个文件');
    } catch (e) {
      debugPrint('[Forge] ZIP 解压失败: $e');
      throw Exception('Forge 安装器解压失败: $e');
    }
    
    var versionEntry = archive.findFile('version.json');
    Map<String, dynamic> forgeJson;
    
    if (versionEntry == null) {
      versionEntry = archive.findFile('install_profile.json');
      if (versionEntry != null) {
        debugPrint('[Forge] 找到 install_profile.json，这是旧版 Forge 格式');
        final installProfile = jsonDecode(utf8.decode(versionEntry.content as List<int>)) as Map<String, dynamic>;
        
        if (installProfile.containsKey('versionInfo')) {
          forgeJson = installProfile['versionInfo'] as Map<String, dynamic>;
        } else {
          versionEntry = archive.findFile('version.json');
          if (versionEntry == null) {
             throw Exception('无效的 Forge 安装器：未找到 version.json');
          }
          forgeJson = jsonDecode(utf8.decode(versionEntry.content as List<int>)) as Map<String, dynamic>;
        }
      } else {
        debugPrint('[Forge] 未找到 version.json');
        throw Exception('无效的 Forge 安装器：未找到 version.json');
      }
    } else {
      debugPrint('[Forge] 找到 version.json');
      forgeJson = jsonDecode(utf8.decode(versionEntry.content as List<int>)) as Map<String, dynamic>;
    }

    
    final files = <DownloadFile>[];
    final libraries = forgeJson['libraries'] as List? ?? [];
    debugPrint('[Forge] 需要下载 ${libraries.length} 个库');
    
    for (final lib in libraries) {
      final downloads = lib['downloads'];
      if (downloads?['artifact'] != null) {
        final artifact = downloads['artifact'];
        final url = artifact['url'] as String?;
        final artifactPath = artifact['path'] as String?;
        if (url != null && url.isNotEmpty && artifactPath != null) {
           files.add(DownloadFile(
             url: _getMirrorUrl(url),
             path: p.join(_librariesDir, artifactPath),
             sha1: artifact['sha1'],
           ));
        }
      } else {
        final name = lib['name'] as String?;
        if (name != null) {
          final libPath = _mavenNameToPath(name);
          if (libPath != null) {
             String baseUrl = lib['url'] as String? ?? '';
             if (baseUrl.isEmpty) {
               if (name.startsWith('net.minecraftforge:')) {
                 baseUrl = 'https://maven.minecraftforge.net/';
               } else if (name.startsWith('net.minecraft:')) {
                 baseUrl = 'https://libraries.minecraft.net/';
               } else if (name.startsWith('org.ow2.asm:') || name.startsWith('cpw.mods:')) {
                 baseUrl = 'https://maven.minecraftforge.net/';
               } else {
                 baseUrl = 'https://repo1.maven.org/maven2/';
               }
             }
             final fullUrl = baseUrl.endsWith('/') ? '$baseUrl$libPath' : '$baseUrl/$libPath';
             
             final bmclapiUrl = fullUrl
                 .replaceFirst('https://libraries.minecraft.net', 'https://bmclapi2.bangbang93.com/maven')
                 .replaceFirst('https://resources.download.minecraft.net', 'https://bmclapi2.bangbang93.com/assets')
                 .replaceFirst('https://piston-meta.mojang.com', 'https://bmclapi2.bangbang93.com')
                 .replaceFirst('https://piston-data.mojang.com', 'https://bmclapi2.bangbang93.com')
                 .replaceFirst('https://launchermeta.mojang.com', 'https://bmclapi2.bangbang93.com')
                 .replaceFirst('https://maven.minecraftforge.net/', 'https://bmclapi2.bangbang93.com/maven/')
                 .replaceFirst('https://maven.minecraftforge.net', 'https://bmclapi2.bangbang93.com/maven')
                 .replaceFirst('https://repo1.maven.org/maven2/', 'https://bmclapi2.bangbang93.com/maven/')
                 .replaceFirst('https://repo1.maven.org/maven2', 'https://bmclapi2.bangbang93.com/maven');

             String primaryUrl;
             List<String> fallbackUrls;

             if (_configService.settings.downloadSource == DownloadSource.bmclapi) {
               primaryUrl = bmclapiUrl;
               fallbackUrls = [fullUrl];
             } else {
               primaryUrl = fullUrl;
               fallbackUrls = [bmclapiUrl];
             }

             files.add(DownloadFile(
               url: primaryUrl,
               path: p.join(_librariesDir, libPath),
               fallbackUrls: fallbackUrls,
             ));
          }
        }
      }
    }

    if (files.isNotEmpty) {
      onStatus?.call('正在下载 ${files.length} 个 Forge 库文件...');
      await _downloadService.downloadFilesInBackground(
        'Forge 库文件',
        files, _configService.settings.concurrentDownloads,
      );
    }

    await tempDir.delete(recursive: true);
    debugPrint('[Forge] 安装完成');
    return _ForgeInstallResult(forgeJson, defaultId);
  }



  Future<Map<String, dynamic>> _installOptiFineAndGetJson(String gameVersion, String optifineVersion, {
    void Function(String)? onStatus,
  }) async {
    onStatus?.call('正在安装 OptiFine $optifineVersion...');
    debugPrint('[OptiFine] 开始安装 (GetJson): $optifineVersion for $gameVersion');
    
    
    final response = await http.get(Uri.parse('https://bmclapi2.bangbang93.com/optifine/$gameVersion'));
    if (response.statusCode != 200) throw Exception('获取 OptiFine 版本列表失败');
    
    final list = jsonDecode(response.body) as List;
    final versionData = list.firstWhere(
      (e) => '${e['type']}_${e['patch']}' == optifineVersion,
      orElse: () => throw Exception('未找到 OptiFine 版本数据: $optifineVersion'),
    );
    
    final type = versionData['type'] as String;
    final patch = versionData['patch'] as String;
    
    debugPrint('[OptiFine] type=$type, patch=$patch');
    
    
    var bmclapiVersion = gameVersion;
    if (bmclapiVersion == '1.8' || bmclapiVersion == '1.9') {
      bmclapiVersion = '$bmclapiVersion.0';
    }
    
    
    onStatus?.call('正在下载 OptiFine...');
    final downloadUrl = 'https://bmclapi2.bangbang93.com/optifine/$bmclapiVersion/$type/$patch';
    debugPrint('[OptiFine] 下载 URL: $downloadUrl');
    
    final tempDir = await Directory.systemTemp.createTemp('optifine_');
    final installerPath = p.join(tempDir.path, 'OptiFine.jar');
    
    final downloadSuccess = await _downloadService.downloadFilesInBackground(
      'OptiFine 安装器',
      [DownloadFile(url: downloadUrl, path: installerPath)],
      1,
    );
    
    if (!downloadSuccess) {
      throw Exception('OptiFine 下载失败');
    }

    final installerFile = File(installerPath);
    if (!await installerFile.exists()) {
      throw Exception('OptiFine 下载失败');
    }
    
    final fileSize = await installerFile.length();
    debugPrint('[OptiFine] 文件大小: $fileSize bytes');
    if (fileSize < 1000) {
      throw Exception('OptiFine 下载失败: 文件无效');
    }

    onStatus?.call('正在解析 OptiFine...');
    final bytes = await installerFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    
    
    final hasPatcher = archive.findFile('optifine/Patcher.class') != null;
    debugPrint('[OptiFine] hasPatcher=$hasPatcher');
    
    
    final optifineLibPath = p.join(_librariesDir, 'optifine', 'OptiFine', '${gameVersion}_$optifineVersion');
    await Directory(optifineLibPath).create(recursive: true);
    
    final optifineJarPath = p.join(optifineLibPath, 'OptiFine-${gameVersion}_$optifineVersion.jar');
    
    if (hasPatcher) {
      
      onStatus?.call('正在运行 OptiFine Patcher...');
      
      
      var clientJar = p.join(_versionsDir, gameVersion, '$gameVersion.jar');
      
      if (!await File(clientJar).exists()) {
        throw Exception('未找到原版客户端 JAR 文件。请先安装原版 Minecraft $gameVersion');
      }
      
      debugPrint('[OptiFine] 使用客户端 JAR: $clientJar');
      
      final javaPath = _configService.settings.javaPath ?? 'java';
      debugPrint('[OptiFine] Patcher 命令: $javaPath -cp $installerPath optifine.Patcher $clientJar $installerPath $optifineJarPath');
      
      final result = await Process.run(javaPath, [
        '-cp', installerPath,
        'optifine.Patcher',
        clientJar,
        installerPath,
        optifineJarPath,
      ]);
      
      debugPrint('[OptiFine] Patcher 退出码: ${result.exitCode}');
      debugPrint('[OptiFine] Patcher stdout: ${result.stdout}');
      debugPrint('[OptiFine] Patcher stderr: ${result.stderr}');
      
      if (result.exitCode != 0) {
        final errorMsg = result.stderr.toString().isNotEmpty 
            ? result.stderr.toString() 
            : result.stdout.toString();
        throw Exception('OptiFine Patcher 失败: $errorMsg');
      }
      
      if (!await File(optifineJarPath).exists()) {
        throw Exception('OptiFine Patcher 未生成输出文件');
      }
    } else {
      
      await installerFile.copy(optifineJarPath);
    }
    
    
    String? launchWrapperVersion;
    final launchWrapperTxt = archive.findFile('launchwrapper-of.txt');
    if (launchWrapperTxt != null) {
      launchWrapperVersion = utf8.decode(launchWrapperTxt.content as List<int>).trim();
      final launchWrapperJar = archive.findFile('launchwrapper-of-$launchWrapperVersion.jar');
      if (launchWrapperJar != null) {
        final lwPath = p.join(_librariesDir, 'optifine', 'launchwrapper-of', launchWrapperVersion);
        await Directory(lwPath).create(recursive: true);
        await File(p.join(lwPath, 'launchwrapper-of-$launchWrapperVersion.jar'))
            .writeAsBytes(launchWrapperJar.content as List<int>);
      }
    } else {
      
      final launchWrapper2 = archive.findFile('launchwrapper-2.0.jar');
      if (launchWrapper2 != null) {
        launchWrapperVersion = '2.0';
        final lwPath = p.join(_librariesDir, 'optifine', 'launchwrapper', '2.0');
        await Directory(lwPath).create(recursive: true);
        await File(p.join(lwPath, 'launchwrapper-2.0.jar'))
            .writeAsBytes(launchWrapper2.content as List<int>);
      }
    }
    
    
    if (launchWrapperVersion == null) {
      onStatus?.call('正在下载 LaunchWrapper...');
      final lwPath = p.join(_librariesDir, 'net', 'minecraft', 'launchwrapper', '1.12', 'launchwrapper-1.12.jar');
      if (!await File(lwPath).exists()) {
        await _downloadService.downloadFilesInBackground(
          'LaunchWrapper',
          [DownloadFile(
            url: _getMirrorUrl('https://libraries.minecraft.net/net/minecraft/launchwrapper/1.12/launchwrapper-1.12.jar'),
            path: lwPath,
          )],
          1,
        );
      }
    }
    
    
    final libraries = <Map<String, dynamic>>[
      {'name': 'optifine:OptiFine:${gameVersion}_$optifineVersion'},
    ];
    
    if (launchWrapperVersion != null) {
      if (launchWrapperVersion == '2.0') {
        libraries.add({'name': 'optifine:launchwrapper:2.0'});
      } else {
        libraries.add({'name': 'optifine:launchwrapper-of:$launchWrapperVersion'});
      }
    } else {
      libraries.add({'name': 'net.minecraft:launchwrapper:1.12'});
    }
    
    
    await tempDir.delete(recursive: true);
    
    debugPrint('[OptiFine] 安装完成 (GetJson)');
    
    
    return {
      'mainClass': 'net.minecraft.launchwrapper.Launch',
      'minecraftArguments': '--tweakClass optifine.OptiFineTweaker',
      'arguments': {
        'game': ['--tweakClass', 'optifine.OptiFineTweaker'],
      },
      'libraries': libraries,
    };
  }

  
  Future<String> installOptiFine(String versionId, String optifineVersion, {
    String? customName,
    void Function(String)? onStatus,
    void Function(double)? onProgress,
  }) async {
    onStatus?.call('正在安装 OptiFine $optifineVersion...');
    debugPrint('[OptiFine] 开始安装: $optifineVersion for $versionId');
    
    
    final installed = getInstalledVersion(versionId);
    if (installed == null) throw Exception('未找到基础版本');
    
    var gameVersion = installed.inheritsFrom ?? versionId;
    
    
    final response = await http.get(Uri.parse('https://bmclapi2.bangbang93.com/optifine/$gameVersion'));
    if (response.statusCode != 200) throw Exception('获取 OptiFine 版本列表失败');
    
    final list = jsonDecode(response.body) as List;
    final versionData = list.firstWhere(
      (e) => '${e['type']}_${e['patch']}' == optifineVersion,
      orElse: () => throw Exception('未找到 OptiFine 版本数据: $optifineVersion'),
    );
    
    final type = versionData['type'] as String; 
    final patch = versionData['patch'] as String; 
    final isPreview = type != 'HD_U'; 
    
    debugPrint('[OptiFine] type=$type, patch=$patch, isPreview=$isPreview');
    
    
    var bmclapiVersion = gameVersion;
    if (bmclapiVersion == '1.8' || bmclapiVersion == '1.9') {
      bmclapiVersion = '$bmclapiVersion.0';
    }
    
    
    
    onStatus?.call('正在下载 OptiFine...');
    final downloadUrl = 'https://bmclapi2.bangbang93.com/optifine/$bmclapiVersion/$type/$patch';
    debugPrint('[OptiFine] 下载 URL: $downloadUrl');
    
    final tempDir = await Directory.systemTemp.createTemp('optifine_');
    final installerPath = p.join(tempDir.path, 'OptiFine.jar');
    
    final downloadSuccess = await _downloadService.downloadFilesInBackground(
      'OptiFine',
      [DownloadFile(url: downloadUrl, path: installerPath)],
      1, onProgress: onProgress,
    );
    
    if (!downloadSuccess) {
      debugPrint('[OptiFine] 下载失败');
      throw Exception('OptiFine 下载失败');
    }

    final installerFile = File(installerPath);
    if (!await installerFile.exists()) {
      debugPrint('[OptiFine] 文件不存在: $installerPath');
      throw Exception('OptiFine 下载失败');
    }
    
    final fileSize = await installerFile.length();
    debugPrint('[OptiFine] 文件大小: $fileSize bytes');
    if (fileSize < 1000) {
      final content = await installerFile.readAsString();
      debugPrint('[OptiFine] 文件内容: $content');
      throw Exception('OptiFine 下载失败: 文件无效');
    }

    onStatus?.call('正在解析 OptiFine...');
    final bytes = await installerFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    
    
    final hasPatcher = archive.findFile('optifine/Patcher.class') != null;
    debugPrint('[OptiFine] hasPatcher=$hasPatcher');
    
    
    final defaultId = '$versionId-OptiFine-$optifineVersion';
    final newVersionId = customName ?? defaultId;
    final newVersionDir = p.join(_versionsDir, newVersionId);
    await Directory(newVersionDir).create(recursive: true);
    
    
    final optifineLibPath = p.join(_librariesDir, 'optifine', 'OptiFine', '${gameVersion}_$optifineVersion');
    await Directory(optifineLibPath).create(recursive: true);
    
    final optifineJarPath = p.join(optifineLibPath, 'OptiFine-${gameVersion}_$optifineVersion.jar');
    
    if (hasPatcher) {
      
      onStatus?.call('正在运行 OptiFine Patcher...');
      
      
      
      final baseVersionId = installed.inheritsFrom ?? versionId;
      var clientJar = p.join(_versionsDir, baseVersionId, '$baseVersionId.jar');
      
      
      if (!await File(clientJar).exists()) {
        
        final pureVersion = gameVersion.split('-').first;
        clientJar = p.join(_versionsDir, pureVersion, '$pureVersion.jar');
      }
      
      if (!await File(clientJar).exists()) {
        debugPrint('[OptiFine] 未找到客户端 JAR: $clientJar');
        throw Exception('未找到原版客户端 JAR 文件。请先安装原版 Minecraft $gameVersion');
      }
      
      debugPrint('[OptiFine] 使用客户端 JAR: $clientJar');
      
      final javaPath = _configService.settings.javaPath ?? 'java';
      debugPrint('[OptiFine] Patcher 命令: $javaPath -cp $installerPath optifine.Patcher $clientJar $installerPath $optifineJarPath');
      
      final result = await Process.run(javaPath, [
        '-cp', installerPath,
        'optifine.Patcher',
        clientJar,
        installerPath,
        optifineJarPath,
      ]);
      
      debugPrint('[OptiFine] Patcher 退出码: ${result.exitCode}');
      debugPrint('[OptiFine] Patcher stdout: ${result.stdout}');
      debugPrint('[OptiFine] Patcher stderr: ${result.stderr}');
      
      if (result.exitCode != 0) {
        final errorMsg = result.stderr.toString().isNotEmpty 
            ? result.stderr.toString() 
            : result.stdout.toString();
        throw Exception('OptiFine Patcher 失败: $errorMsg');
      }
      
      
      if (!await File(optifineJarPath).exists()) {
        throw Exception('OptiFine Patcher 未生成输出文件');
      }
    } else {
      
      await installerFile.copy(optifineJarPath);
    }
    
    
    String? launchWrapperVersion;
    final launchWrapperTxt = archive.findFile('launchwrapper-of.txt');
    if (launchWrapperTxt != null) {
      launchWrapperVersion = utf8.decode(launchWrapperTxt.content as List<int>).trim();
      final launchWrapperJar = archive.findFile('launchwrapper-of-$launchWrapperVersion.jar');
      if (launchWrapperJar != null) {
        final lwPath = p.join(_librariesDir, 'optifine', 'launchwrapper-of', launchWrapperVersion);
        await Directory(lwPath).create(recursive: true);
        await File(p.join(lwPath, 'launchwrapper-of-$launchWrapperVersion.jar'))
            .writeAsBytes(launchWrapperJar.content as List<int>);
      }
    } else {
      
      final launchWrapper2 = archive.findFile('launchwrapper-2.0.jar');
      if (launchWrapper2 != null) {
        launchWrapperVersion = '2.0';
        final lwPath = p.join(_librariesDir, 'optifine', 'launchwrapper', '2.0');
        await Directory(lwPath).create(recursive: true);
        await File(p.join(lwPath, 'launchwrapper-2.0.jar'))
            .writeAsBytes(launchWrapper2.content as List<int>);
      }
    }
    
    
    final libraries = <Map<String, dynamic>>[
      {'name': 'optifine:OptiFine:${gameVersion}_$optifineVersion'},
    ];
    
    if (launchWrapperVersion != null) {
      if (launchWrapperVersion == '2.0') {
        libraries.add({'name': 'optifine:launchwrapper:2.0'});
      } else {
        libraries.add({'name': 'optifine:launchwrapper-of:$launchWrapperVersion'});
      }
    } else {
      libraries.add({'name': 'net.minecraft:launchwrapper:1.12'});
    }
    
    final versionJson = {
      'id': newVersionId,
      'inheritsFrom': versionId,
      'type': 'release',
      'mainClass': 'net.minecraft.launchwrapper.Launch',
      'minecraftArguments': installed.minecraftArguments != null
          ? '${installed.minecraftArguments} --tweakClass optifine.OptiFineTweaker'
          : null,
      'arguments': {
        'game': ['--tweakClass', 'optifine.OptiFineTweaker'],
      },
      'libraries': libraries,
    };
    
    await File(p.join(newVersionDir, '$newVersionId.json')).writeAsString(jsonEncode(versionJson));
    
    
    if (launchWrapperVersion == null) {
      onStatus?.call('正在下载 LaunchWrapper...');
      final lwPath = p.join(_librariesDir, 'net', 'minecraft', 'launchwrapper', '1.12', 'launchwrapper-1.12.jar');
      if (!await File(lwPath).exists()) {
        await _downloadService.downloadFilesInBackground(
          'LaunchWrapper',
          [DownloadFile(
            url: _getMirrorUrl('https://libraries.minecraft.net/net/minecraft/launchwrapper/1.12/launchwrapper-1.12.jar'),
            path: lwPath,
          )],
          1,
        );
      }
    }
    
    
    await tempDir.delete(recursive: true);
    
    await _loadInstalledVersions();
    onStatus?.call('OptiFine 安装完成！');
    
    return newVersionId;
  }
}

class DownloadFile {
  final String url;
  final String path;
  final String? sha1;
  final int? size;
  final List<String> fallbackUrls;

  DownloadFile({
    required this.url,
    required this.path,
    this.sha1,
    this.size,
    this.fallbackUrls = const [],
  });
}

class _ForgeInstallResult {
  final Map<String, dynamic> json;
  final String defaultId;
  _ForgeInstallResult(this.json, this.defaultId);
}
