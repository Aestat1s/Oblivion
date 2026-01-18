
enum ResourceType {
  mod,
  modpack,
  shader,
  resourcePack,
  world,
  datapack,
}


enum ResourceSource { modrinth, curseforge }


class ResourceItem {
  final String id;
  final String slug;
  final String title;
  final String description;
  final String? author;
  final List<String> categories;
  final String? iconUrl;
  final String? pageUrl;
  final int downloads;
  final DateTime? dateCreated;
  final DateTime? dateModified;
  final ResourceSource source;
  final ResourceType type;

  ResourceItem({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    this.author,
    this.categories = const [],
    this.iconUrl,
    this.pageUrl,
    this.downloads = 0,
    this.dateCreated,
    this.dateModified,
    this.source = ResourceSource.modrinth,
    required this.type,
  });

  factory ResourceItem.fromModrinthSearch(Map<String, dynamic> json, ResourceType type) {
    return ResourceItem(
      id: json['project_id'] ?? '',
      slug: json['slug'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      author: json['author'],
      categories: List<String>.from(json['categories'] ?? []),
      iconUrl: json['icon_url'],
      pageUrl: 'https://modrinth.com/${_getModrinthPath(type)}/${json['slug']}',
      downloads: json['downloads'] ?? 0,
      dateCreated: json['date_created'] != null ? DateTime.tryParse(json['date_created']) : null,
      dateModified: json['date_modified'] != null ? DateTime.tryParse(json['date_modified']) : null,
      source: ResourceSource.modrinth,
      type: type,
    );
  }

  factory ResourceItem.fromCurseforge(Map<String, dynamic> json, ResourceType type) {
    final data = json.containsKey('id') ? json : (json['data'] ?? json);
    return ResourceItem(
      id: '${data['id']}',
      slug: data['slug'] ?? '',
      title: data['name'] ?? '',
      description: data['summary'] ?? '',
      author: (data['authors'] as List?)?.isNotEmpty == true ? data['authors'][0]['name'] : null,
      categories: (data['categories'] as List?)?.map((c) => c['name'] as String).toList() ?? [],
      iconUrl: data['logo']?['url'],
      pageUrl: data['links']?['websiteUrl'],
      downloads: data['downloadCount'] ?? 0,
      dateCreated: data['dateCreated'] != null ? DateTime.tryParse(data['dateCreated']) : null,
      dateModified: data['dateModified'] != null ? DateTime.tryParse(data['dateModified']) : null,
      source: ResourceSource.curseforge,
      type: type,
    );
  }

  static String _getModrinthPath(ResourceType type) {
    return switch (type) {
      ResourceType.mod => 'mod',
      ResourceType.modpack => 'modpack',
      ResourceType.shader => 'shader',
      ResourceType.resourcePack => 'resourcepack',
      ResourceType.world => 'world',
      ResourceType.datapack => 'datapack',
    };
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'slug': slug,
    'title': title,
    'description': description,
    'author': author,
    'categories': categories,
    'iconUrl': iconUrl,
    'pageUrl': pageUrl,
    'downloads': downloads,
    'dateCreated': dateCreated?.toIso8601String(),
    'dateModified': dateModified?.toIso8601String(),
    'source': source.name,
    'type': type.name,
  };

  factory ResourceItem.fromJson(Map<String, dynamic> json) {
    return ResourceItem(
      id: json['id'] ?? '',
      slug: json['slug'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      author: json['author'],
      categories: List<String>.from(json['categories'] ?? []),
      iconUrl: json['iconUrl'],
      pageUrl: json['pageUrl'],
      downloads: json['downloads'] ?? 0,
      dateCreated: json['dateCreated'] != null ? DateTime.tryParse(json['dateCreated']) : null,
      dateModified: json['dateModified'] != null ? DateTime.tryParse(json['dateModified']) : null,
      source: ResourceSource.values.firstWhere((e) => e.name == json['source'], orElse: () => ResourceSource.modrinth),
      type: ResourceType.values.firstWhere((e) => e.name == json['type'], orElse: () => ResourceType.mod),
    );
  }
}


class ResourceVersion {
  final String id;
  final String projectId;
  final String name;
  final String versionNumber;
  final String? changelog;
  final DateTime? datePublished;
  final ResourceVersionType versionType;
  final List<ResourceFile> files;
  final List<String> gameVersions;
  final List<String> loaders;

  ResourceVersion({
    required this.id,
    required this.projectId,
    required this.name,
    required this.versionNumber,
    this.changelog,
    this.datePublished,
    this.versionType = ResourceVersionType.release,
    this.files = const [],
    this.gameVersions = const [],
    this.loaders = const [],
  });

  factory ResourceVersion.fromModrinth(Map<String, dynamic> json) {
    ResourceVersionType type;
    switch (json['version_type']) {
      case 'release': type = ResourceVersionType.release; break;
      case 'beta': type = ResourceVersionType.beta; break;
      case 'alpha': type = ResourceVersionType.alpha; break;
      default: type = ResourceVersionType.release;
    }
    return ResourceVersion(
      id: json['id'] ?? '',
      projectId: json['project_id'] ?? '',
      name: json['name'] ?? '',
      versionNumber: json['version_number'] ?? '',
      changelog: json['changelog'],
      datePublished: json['date_published'] != null ? DateTime.tryParse(json['date_published']) : null,
      versionType: type,
      files: (json['files'] as List?)?.map((f) => ResourceFile.fromModrinth(f)).toList() ?? [],
      gameVersions: List<String>.from(json['game_versions'] ?? []),
      loaders: List<String>.from(json['loaders'] ?? []),
    );
  }

  factory ResourceVersion.fromCurseforge(Map<String, dynamic> json) {
    ResourceVersionType type;
    switch (json['releaseType']) {
      case 1: type = ResourceVersionType.release; break;
      case 2: type = ResourceVersionType.beta; break;
      case 3: type = ResourceVersionType.alpha; break;
      default: type = ResourceVersionType.release;
    }
    return ResourceVersion(
      id: '${json['id']}',
      projectId: '${json['modId']}',
      name: json['displayName'] ?? '',
      versionNumber: json['displayName'] ?? '',
      datePublished: json['fileDate'] != null ? DateTime.tryParse(json['fileDate']) : null,
      versionType: type,
      files: [ResourceFile.fromCurseforge(json)],
      gameVersions: List<String>.from(json['gameVersions'] ?? []),
      loaders: [],
    );
  }
}


class ResourceFile {
  final String url;
  final String filename;
  final int size;
  final Map<String, String> hashes;
  final bool primary;

  ResourceFile({
    required this.url,
    required this.filename,
    this.size = 0,
    this.hashes = const {},
    this.primary = false,
  });

  factory ResourceFile.fromModrinth(Map<String, dynamic> json) {
    return ResourceFile(
      url: json['url'] ?? '',
      filename: json['filename'] ?? '',
      size: json['size'] ?? 0,
      hashes: Map<String, String>.from(json['hashes'] ?? {}),
      primary: json['primary'] ?? false,
    );
  }

  factory ResourceFile.fromCurseforge(Map<String, dynamic> json) {
    String url = json['downloadUrl'] ?? '';
    final fileName = json['fileName'] ?? '';
    final fileId = json['id']?.toString() ?? '';
    
    
    if (url.isEmpty && fileId.isNotEmpty && fileName.isNotEmpty) {
      
      final part1 = fileId.length >= 4 ? fileId.substring(0, 4) : fileId;
      final part2 = fileId.length > 4 ? int.tryParse(fileId.substring(4))?.toString() ?? fileId.substring(4) : '0';
      url = 'https://edge.forgecdn.net/files/$part1/$part2/${Uri.encodeComponent(fileName)}';
    }
    
    return ResourceFile(
      url: url,
      filename: fileName,
      size: json['fileLength'] ?? 0,
      hashes: {},
      primary: true,
    );
  }
}

enum ResourceVersionType { release, beta, alpha }
