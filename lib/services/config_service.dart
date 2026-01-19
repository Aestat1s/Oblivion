import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/config.dart';

class ConfigService extends ChangeNotifier {
  LauncherConfig _config = LauncherConfig();
  String _configPath = '';
  bool _isLoaded = false;

  LauncherConfig get config => _config;
  bool get isLoaded => _isLoaded;
  GlobalSettings get settings => _config.globalSettings;

  String get gameDirectory {
    if (_config.globalSettings.gameDirectory.isNotEmpty) {
      return _config.globalSettings.gameDirectory;
    }
    return p.join(Platform.environment['APPDATA'] ?? '', '.minecraft');
  }

  Future<void> load() async {
    final appDir = await getApplicationSupportDirectory();
    _configPath = p.join(appDir.path, 'config.json');
    
    final file = File(_configPath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        _config = LauncherConfig.fromJson(jsonDecode(content));
      } catch (e) {
        _config = LauncherConfig();
      }
    }
    
    if (_config.globalSettings.gameDirectory.isEmpty) {
      _config.globalSettings.gameDirectory = 
          p.join(Platform.environment['APPDATA'] ?? '', '.minecraft');
    }
    
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    final file = File(_configPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_config.toJson()));
    notifyListeners();
  }

  void updateSettings(GlobalSettings settings) {
    _config.globalSettings = settings;
    save();
  }

  void setGameDirectory(String path) {
    _config.globalSettings.gameDirectory = path;
    save();
  }

  void setMemory(int min, int max) {
    _config.globalSettings.minMemory = min;
    _config.globalSettings.maxMemory = max;
    save();
  }

  void setJavaPath(String? path) {
    _config.globalSettings.javaPath = path;
    _config.globalSettings.autoSelectJava = path == null;
    save();
  }

  void setDownloadSource(DownloadSource source) {
    _config.globalSettings.downloadSource = source;
    save();
  }

  void setConcurrentDownloads(int count) {
    _config.globalSettings.concurrentDownloads = count;
    save();
  }

  void setEnableAnimations(bool enable) {
    _config.globalSettings.enableAnimations = enable;
    save();
  }
}
