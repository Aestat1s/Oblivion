import 'package:flutter/material.dart' show ThemeMode;
import 'account.dart';

enum DownloadSource { official, bmclapi }
enum IsolationType { none, partial, full }
enum BackgroundType { none, image, randomImage }
enum ThemeColorSource { system, customBackground, manual }

class LauncherConfig {
  int version;
  List<Account> accounts;
  String? selectedAccountId;
  List<VersionProfile> versionProfiles;
  String? selectedVersionId;
  GlobalSettings globalSettings;

  LauncherConfig({
    this.version = 1,
    List<Account>? accounts,
    this.selectedAccountId,
    List<VersionProfile>? versionProfiles,
    this.selectedVersionId,
    GlobalSettings? globalSettings,
  })  : accounts = accounts ?? [],
        versionProfiles = versionProfiles ?? [],
        globalSettings = globalSettings ?? GlobalSettings();

  Map<String, dynamic> toJson() => {
    'version': version,
    'accounts': accounts.map((a) => a.toJson()).toList(),
    'selectedAccountId': selectedAccountId,
    'versionProfiles': versionProfiles.map((p) => p.toJson()).toList(),
    'selectedVersionId': selectedVersionId,
    'globalSettings': globalSettings.toJson(),
  };

  factory LauncherConfig.fromJson(Map<String, dynamic> json) => LauncherConfig(
    version: json['version'] ?? 1,
    accounts: (json['accounts'] as List?)?.map((a) => Account.fromJson(a)).toList() ?? [],
    selectedAccountId: json['selectedAccountId'],
    versionProfiles: (json['versionProfiles'] as List?)?.map((p) => VersionProfile.fromJson(p)).toList() ?? [],
    selectedVersionId: json['selectedVersionId'],
    globalSettings: json['globalSettings'] != null
        ? GlobalSettings.fromJson(json['globalSettings'])
        : GlobalSettings(),
  );
}

class GlobalSettings {
  String gameDirectory;
  String? javaPath;
  bool autoSelectJava;
  bool autoCompleteFiles;
  bool dynamicMemory;
  int minMemory;
  int maxMemory;
  String jvmArgs;
  String gameArgs;
  int windowWidth;
  int windowHeight;
  bool fullscreen;
  DownloadSource downloadSource;
  int concurrentDownloads;
  ThemeMode themeMode;
  String language;
  bool checkUpdates;
  IsolationType defaultIsolation;
  
  // 个性化设置
  BackgroundType backgroundType;
  String? customBackgroundPath;
  String? randomImageApi;
  double backgroundBlur;
  bool enableCustomColor;
  ThemeColorSource themeColorSource;
  int? customThemeColor;
  String? customFontFamily;
  double windowOpacity;

  GlobalSettings({
    this.gameDirectory = '',
    this.javaPath,
    this.autoSelectJava = true,
    this.autoCompleteFiles = true,
    this.dynamicMemory = true,
    this.minMemory = 512,
    this.maxMemory = 4096,
    this.jvmArgs = '',
    this.gameArgs = '',
    this.windowWidth = 854,
    this.windowHeight = 480,
    this.fullscreen = false,
    this.downloadSource = DownloadSource.official,
    this.concurrentDownloads = 64,
    this.themeMode = ThemeMode.dark,
    this.language = 'zh',
    this.checkUpdates = true,
    this.defaultIsolation = IsolationType.none,
    this.backgroundType = BackgroundType.none,
    this.customBackgroundPath,
    this.randomImageApi = 'https://t.alcy.cc/pc',
    this.backgroundBlur = 0.0,
    this.enableCustomColor = false,
    this.themeColorSource = ThemeColorSource.system,
    this.customThemeColor,
    this.customFontFamily,
    this.windowOpacity = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'gameDirectory': gameDirectory,
    'javaPath': javaPath,
    'autoSelectJava': autoSelectJava,
    'autoCompleteFiles': autoCompleteFiles,
    'dynamicMemory': dynamicMemory,
    'minMemory': minMemory,
    'maxMemory': maxMemory,
    'jvmArgs': jvmArgs,
    'gameArgs': gameArgs,
    'windowWidth': windowWidth,
    'windowHeight': windowHeight,
    'fullscreen': fullscreen,
    'downloadSource': downloadSource.index,
    'concurrentDownloads': concurrentDownloads,
    'themeMode': themeMode.index,
    'language': language,
    'checkUpdates': checkUpdates,
    'defaultIsolation': defaultIsolation.index,
    'backgroundType': backgroundType.index,
    'customBackgroundPath': customBackgroundPath,
    'randomImageApi': randomImageApi,
    'backgroundBlur': backgroundBlur,
    'enableCustomColor': enableCustomColor,
    'themeColorSource': themeColorSource.index,
    'customThemeColor': customThemeColor,
    'customFontFamily': customFontFamily,
    'windowOpacity': windowOpacity,
  };

  factory GlobalSettings.fromJson(Map<String, dynamic> json) => GlobalSettings(
    gameDirectory: json['gameDirectory'] ?? '',
    javaPath: json['javaPath'],
    autoSelectJava: json['autoSelectJava'] ?? true,
    autoCompleteFiles: json['autoCompleteFiles'] ?? true,
    dynamicMemory: json['dynamicMemory'] ?? true,
    minMemory: json['minMemory'] ?? 512,
    maxMemory: json['maxMemory'] ?? 4096,
    jvmArgs: json['jvmArgs'] ?? '',
    gameArgs: json['gameArgs'] ?? '',
    windowWidth: json['windowWidth'] ?? 854,
    windowHeight: json['windowHeight'] ?? 480,
    fullscreen: json['fullscreen'] ?? false,
    downloadSource: DownloadSource.values[json['downloadSource'] ?? 0],
    concurrentDownloads: json['concurrentDownloads'] ?? 64,
    themeMode: ThemeMode.values[json['themeMode'] ?? json['theme'] ?? 2],
    language: json['language'] ?? 'zh',
    checkUpdates: json['checkUpdates'] ?? true,
    defaultIsolation: IsolationType.values[json['defaultIsolation'] ?? 0],
    backgroundType: BackgroundType.values[json['backgroundType'] ?? 0],
    customBackgroundPath: json['customBackgroundPath'],
    randomImageApi: json['randomImageApi'] ?? json['randomImageApiHorizontal'] ?? 'https://t.alcy.cc/pc',
    backgroundBlur: json['backgroundBlur']?.toDouble() ?? 0.0,
    enableCustomColor: json['enableCustomColor'] ?? false,
    themeColorSource: ThemeColorSource.values[json['themeColorSource'] ?? 0],
    customThemeColor: json['customThemeColor'],
    customFontFamily: json['customFontFamily'],
    windowOpacity: json['windowOpacity']?.toDouble() ?? 1.0,
  );
}

class VersionProfile {
  final String versionId;
  String displayName;
  IsolationType isolation;
  String? javaPath;
  bool? autoSelectJava;
  int? minMemory;
  int? maxMemory;
  String? jvmArgs;
  String? gameArgs;
  int? windowWidth;
  int? windowHeight;
  bool? fullscreen;
  DateTime createdAt;
  DateTime lastPlayed;

  VersionProfile({
    required this.versionId,
    String? displayName,
    this.isolation = IsolationType.none,
    this.javaPath,
    this.autoSelectJava,
    this.minMemory,
    this.maxMemory,
    this.jvmArgs,
    this.gameArgs,
    this.windowWidth,
    this.windowHeight,
    this.fullscreen,
    DateTime? createdAt,
    DateTime? lastPlayed,
  })  : displayName = displayName ?? versionId,
        createdAt = createdAt ?? DateTime.now(),
        lastPlayed = lastPlayed ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'versionId': versionId,
    'displayName': displayName,
    'isolation': isolation.index,
    'javaPath': javaPath,
    'autoSelectJava': autoSelectJava,
    'minMemory': minMemory,
    'maxMemory': maxMemory,
    'jvmArgs': jvmArgs,
    'gameArgs': gameArgs,
    'windowWidth': windowWidth,
    'windowHeight': windowHeight,
    'fullscreen': fullscreen,
    'createdAt': createdAt.toIso8601String(),
    'lastPlayed': lastPlayed.toIso8601String(),
  };

  factory VersionProfile.fromJson(Map<String, dynamic> json) => VersionProfile(
    versionId: json['versionId'],
    displayName: json['displayName'],
    isolation: IsolationType.values[json['isolation'] ?? 0],
    javaPath: json['javaPath'],
    autoSelectJava: json['autoSelectJava'],
    minMemory: json['minMemory'],
    maxMemory: json['maxMemory'],
    jvmArgs: json['jvmArgs'],
    gameArgs: json['gameArgs'],
    windowWidth: json['windowWidth'],
    windowHeight: json['windowHeight'],
    fullscreen: json['fullscreen'],
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    lastPlayed: DateTime.tryParse(json['lastPlayed'] ?? '') ?? DateTime.now(),
  );

  
  String getGameDir(String baseDir, String versionsDir) {
    switch (isolation) {
      case IsolationType.none:
        return baseDir;
      case IsolationType.partial:
        
        return '$versionsDir/$versionId';
      case IsolationType.full:
        
        return '$versionsDir/$versionId/.minecraft';
    }
  }
}
