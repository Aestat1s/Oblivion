enum VersionType { release, snapshot, oldBeta, oldAlpha }
enum ModLoaderType { none, forge, neoForge, fabric, quilt, liteLoader, optiFine }

class GameVersion {
  final String id;
  final String type;
  final String url;
  final DateTime time;
  final DateTime releaseTime;
  final String? sha1;

  GameVersion({
    required this.id,
    required this.type,
    required this.url,
    required this.time,
    required this.releaseTime,
    this.sha1,
  });

  VersionType get versionType => switch (type) {
    'release' => VersionType.release,
    'snapshot' => VersionType.snapshot,
    'old_beta' => VersionType.oldBeta,
    'old_alpha' => VersionType.oldAlpha,
    _ => VersionType.release,
  };

  factory GameVersion.fromJson(Map<String, dynamic> json) => GameVersion(
    id: json['id'],
    type: json['type'],
    url: json['url'],
    time: DateTime.parse(json['time']),
    releaseTime: DateTime.parse(json['releaseTime']),
    sha1: json['sha1'],
  );
}

class InstalledVersion {
  final String id;
  final String type;
  final String? inheritsFrom;
  final String? mainClass;
  final String? assets;
  final int? javaVersion;
  final String? minecraftArguments;
  final List<ModLoaderInfo> modLoaders;
  final DateTime installedTime;
  final String path;

  InstalledVersion({
    required this.id,
    required this.type,
    this.inheritsFrom,
    this.mainClass,
    this.assets,
    this.javaVersion,
    this.minecraftArguments,
    this.modLoaders = const [],
    DateTime? installedTime,
    required this.path,
  }) : installedTime = installedTime ?? DateTime.now();

  String get displayName => modLoaders.isNotEmpty
      ? '$id (${modLoaders.map((m) => m.type.name).join(', ')})'
      : id;

  
  String get baseVersion => inheritsFrom ?? id;

  factory InstalledVersion.fromJson(Map<String, dynamic> json, String path) {
    final modLoaders = <ModLoaderInfo>[];
    
    
    final mainClass = json['mainClass'] as String?;
    if (mainClass != null) {
      if (mainClass.contains('fabric')) {
        modLoaders.add(ModLoaderInfo(type: ModLoaderType.fabric, version: ''));
      } else if (mainClass.contains('forge') || mainClass.contains('fml')) {
        modLoaders.add(ModLoaderInfo(type: ModLoaderType.forge, version: ''));
      } else if (mainClass.contains('quilt')) {
        modLoaders.add(ModLoaderInfo(type: ModLoaderType.quilt, version: ''));
      }
    }

    return InstalledVersion(
      id: json['id'],
      type: json['type'] ?? 'release',
      inheritsFrom: json['inheritsFrom'],
      mainClass: mainClass,
      assets: json['assets'] ?? json['assetIndex']?['id'],
      javaVersion: json['javaVersion']?['majorVersion'],
      minecraftArguments: json['minecraftArguments'],
      modLoaders: modLoaders,
      path: path,
    );
  }
}

class ModLoaderInfo {
  final ModLoaderType type;
  final String version;

  ModLoaderInfo({required this.type, required this.version});
}

class VersionManifest {
  final LatestVersion latest;
  final List<GameVersion> versions;

  VersionManifest({required this.latest, required this.versions});

  factory VersionManifest.fromJson(Map<String, dynamic> json) => VersionManifest(
    latest: LatestVersion.fromJson(json['latest']),
    versions: (json['versions'] as List).map((v) => GameVersion.fromJson(v)).toList(),
  );
}

class LatestVersion {
  final String release;
  final String snapshot;

  LatestVersion({required this.release, required this.snapshot});

  factory LatestVersion.fromJson(Map<String, dynamic> json) => LatestVersion(
    release: json['release'],
    snapshot: json['snapshot'],
  );
}

class ModLoaderVersion {
  final String version;
  final String gameVersion;
  final ModLoaderType type;
  final bool stable;
  final int? buildNumber;

  ModLoaderVersion({
    required this.version,
    required this.gameVersion,
    required this.type,
    this.stable = true,
    this.buildNumber,
  });

  
  
  String get uniqueId => buildNumber != null ? buildNumber.toString() : version;

  
  String get displayName => version;
}
