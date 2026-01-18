import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/resource_item.dart';
import 'download_service.dart';
import 'game_service.dart' show DownloadFile;
import 'debug_logger.dart';

class ResourceSearchStorage {
  int modrinthOffset = 0;
  int modrinthTotal = -1;
  int curseForgeOffset = 0;
  int curseForgeTotal = -1;
  List<ResourceItem> results = [];
  String? errorMessage;

  void reset() {
    modrinthOffset = 0;
    modrinthTotal = -1;
    curseForgeOffset = 0;
    curseForgeTotal = -1;
    results = [];
    errorMessage = null;
  }
}

class ResourceSearchRequest {
  final ResourceSource source;
  final ResourceType type;
  final String query;
  final String? gameVersion;
  final String? category;
  final String? loader;
  final ResourceSortType sortType;
  final int pageSize;

  ResourceSearchRequest({
    required this.source,
    required this.type,
    this.query = '',
    this.gameVersion,
    this.category,
    this.loader,
    this.sortType = ResourceSortType.downloads,
    this.pageSize = 20,
  });
}

enum ResourceSortType { relevance, downloads, updated, newest }

class ResourceDownloadService extends ChangeNotifier {
  static const String _modrinthApi = 'https://api.modrinth.com/v2';
  static const String _modrinthMirror = 'https://mod.mcimirror.top/modrinth/v2';
  static const String _curseforgeApi = 'https://api.curseforge.com/v1';
  static const String _curseforgeMirror = 'https://mod.mcimirror.top/curseforge/v1';

  final DownloadService _downloadService;
  final ResourceSearchStorage _storage = ResourceSearchStorage();
  
  ResourceSearchRequest? _currentRequest;
  bool _isSearching = false;
  int _currentPage = 0;
  List<ResourceCategory> _categories = [];
  int _searchVersion = 0; 

  ResourceDownloadService(this._downloadService);

  List<ResourceItem> get searchResults => _storage.results;
  List<ResourceCategory> get categories => _categories;
  bool get isSearching => _isSearching;
  String get searchError => _storage.errorMessage ?? '';
  int get currentPage => _currentPage;
  ResourceSource get currentSource => _currentRequest?.source ?? ResourceSource.modrinth;
  ResourceType get currentType => _currentRequest?.type ?? ResourceType.mod;
  bool get hasSearched => _currentRequest != null;

  int get totalHits {
    if (_currentRequest == null) return 0;
    return _currentRequest!.source == ResourceSource.modrinth
        ? (_storage.modrinthTotal > 0 ? _storage.modrinthTotal : 0)
        : (_storage.curseForgeTotal > 0 ? _storage.curseForgeTotal : 0);
  }

  int get totalPages {
    final total = totalHits;
    if (total <= 0) return 0;
    return (total / (_currentRequest?.pageSize ?? 20)).ceil();
  }

  void setSource(ResourceSource source) {
    if (_currentRequest?.source == source) return;
    _storage.reset();
    _currentPage = 0;
    _currentRequest = ResourceSearchRequest(
      source: source,
      type: _currentRequest?.type ?? ResourceType.mod,
      query: _currentRequest?.query ?? '',
      gameVersion: _currentRequest?.gameVersion,
      category: _currentRequest?.category,
      loader: _currentRequest?.loader,
      sortType: _currentRequest?.sortType ?? ResourceSortType.downloads,
    );
    notifyListeners();
  }

  void setType(ResourceType type) {
    if (_currentRequest?.type == type) return;
    _storage.reset();
    _currentPage = 0;
    _currentRequest = ResourceSearchRequest(
      source: _currentRequest?.source ?? ResourceSource.modrinth,
      type: type,
      query: '',
      sortType: ResourceSortType.downloads,
    );
    notifyListeners();
  }

  Future<void> searchResources({
    ResourceType? type,
    String query = '',
    String? gameVersion,
    String? category,
    String? loader,
    ResourceSortType sortType = ResourceSortType.downloads,
    int page = 0,
    int pageSize = 20,
  }) async {
    if (_isSearching) return;

    final source = _currentRequest?.source ?? ResourceSource.modrinth;
    final resourceType = type ?? _currentRequest?.type ?? ResourceType.mod;

    final newRequest = ResourceSearchRequest(
      source: source,
      type: resourceType,
      query: query,
      gameVersion: gameVersion,
      category: category,
      loader: loader,
      sortType: sortType,
      pageSize: pageSize,
    );

    _currentRequest = newRequest;
    _currentPage = page;
    _isSearching = true;
    _storage.errorMessage = null;
    _storage.results = [];
    _searchVersion++; 
    final currentVersion = _searchVersion;
    notifyListeners();

    try {
      final offset = page * pageSize;
      if (source == ResourceSource.modrinth) {
        _storage.modrinthOffset = offset;
        await _searchModrinth(newRequest);
      } else {
        _storage.curseForgeOffset = offset;
        await _searchCurseforge(newRequest);
      }
      
      if (_searchVersion != currentVersion) {
        return;
      }
    } catch (e) {
      if (_searchVersion != currentVersion) {
        return;
      }
      _storage.errorMessage = e.toString();
      debugLog('[ResourceDownload] Search error: $e');
    } finally {
      if (_searchVersion == currentVersion) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  Future<void> _searchModrinth(ResourceSearchRequest request) async {
    final facets = <String>[];
    facets.add('["project_type:${_getModrinthProjectType(request.type)}"]');
    
    if (request.gameVersion != null && request.gameVersion!.isNotEmpty) {
      facets.add('["versions:\'${request.gameVersion}\'"]');
    }
    if (request.category != null && request.category!.isNotEmpty) {
      facets.add('["categories:\'${request.category}\'"]');
    }
    if (request.loader != null && request.loader!.isNotEmpty) {
      facets.add('["categories:\'${request.loader}\'"]');
    }

    final params = <String, String>{
      'limit': '${request.pageSize}',
      'index': _convertSortType(request.sortType),
    };
    
    if (request.query.isNotEmpty) params['query'] = request.query;
    if (_storage.modrinthOffset > 0) params['offset'] = '${_storage.modrinthOffset}';
    if (facets.isNotEmpty) params['facets'] = '[${facets.join(",")}]';

    final urls = [_modrinthMirror, _modrinthMirror, _modrinthApi];
    http.Response? response;
    String? lastError;

    for (final baseUrl in urls) {
      try {
        final uri = Uri.parse('$baseUrl/search').replace(queryParameters: params);
        response = await http.get(uri, headers: _modrinthHeaders)
            .timeout(Duration(seconds: baseUrl == _modrinthMirror ? 10 : 15));
        if (response.statusCode == 200) break;
        lastError = 'HTTP ${response.statusCode}';
      } catch (e) {
        lastError = e.toString();
      }
    }

    if (response == null || response.statusCode != 200) {
      throw Exception('Modrinth 搜索失败: $lastError');
    }

    final data = jsonDecode(response.body);
    final hits = data['hits'] as List;
    _storage.modrinthTotal = data['total_hits'] as int;
    _storage.results = hits.map((hit) => ResourceItem.fromModrinthSearch(hit, request.type)).toList();
  }

  Future<void> _searchCurseforge(ResourceSearchRequest request) async {
    final params = <String, String>{
      'gameId': '432',
      'classId': _getCurseforgeClassId(request.type),
      'pageSize': '${request.pageSize}',
      'sortOrder': 'desc',
      'sortField': _convertCurseforgeSortType(request.sortType),
    };

    if (request.query.isNotEmpty) params['searchFilter'] = request.query;
    if (_storage.curseForgeOffset > 0) params['index'] = '${_storage.curseForgeOffset}';
    if (request.gameVersion != null) params['gameVersion'] = request.gameVersion!;

    final urls = [_curseforgeMirror, _curseforgeMirror, _curseforgeApi];
    http.Response? response;
    String? lastError;

    for (final baseUrl in urls) {
      try {
        final uri = Uri.parse('$baseUrl/mods/search').replace(queryParameters: params);
        response = await http.get(uri, headers: _curseforgeHeaders(baseUrl))
            .timeout(Duration(seconds: baseUrl == _curseforgeMirror ? 10 : 15));
        if (response.statusCode == 200) break;
        lastError = 'HTTP ${response.statusCode}';
      } catch (e) {
        lastError = e.toString();
      }
    }

    if (response == null || response.statusCode != 200) {
      throw Exception('CurseForge 搜索失败: $lastError');
    }

    final data = jsonDecode(response.body);
    final mods = data['data'] as List? ?? [];
    final pagination = data['pagination'] as Map<String, dynamic>?;
    _storage.curseForgeTotal = pagination?['totalCount'] ?? mods.length;
    _storage.results = mods.map((m) => ResourceItem.fromCurseforge(m, request.type)).toList();
  }

  Future<List<ResourceVersion>> getResourceVersions(String projectId, {
    String? gameVersion,
    String? loader,
    ResourceSource? source,
  }) async {
    final effectiveSource = source ?? currentSource;
    if (effectiveSource == ResourceSource.modrinth) {
      return _getModrinthVersions(projectId, gameVersion: gameVersion, loader: loader);
    } else {
      return _getCurseforgeVersions(projectId, gameVersion: gameVersion);
    }
  }

  Future<List<ResourceVersion>> _getModrinthVersions(String projectId, {
    String? gameVersion,
    String? loader,
  }) async {
    final params = <String, String>{};
    if (gameVersion != null) params['game_versions'] = '["$gameVersion"]';
    if (loader != null) params['loaders'] = '["$loader"]';

    final urls = [_modrinthMirror, _modrinthApi];
    for (final baseUrl in urls) {
      try {
        var url = '$baseUrl/project/$projectId/version';
        if (params.isNotEmpty) {
          url = Uri.parse(url).replace(queryParameters: params).toString();
        }
        final response = await http.get(Uri.parse(url), headers: _modrinthHeaders)
            .timeout(Duration(seconds: baseUrl == _modrinthMirror ? 10 : 15));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as List;
          return data.map((v) => ResourceVersion.fromModrinth(v)).toList();
        }
      } catch (e) {
        debugLog('[ResourceDownload] Failed to get versions from $baseUrl: $e');
      }
    }
    return [];
  }

  Future<List<ResourceVersion>> _getCurseforgeVersions(String projectId, {
    String? gameVersion,
  }) async {
    final params = <String, String>{'pageSize': '10000'};
    if (gameVersion != null) params['gameVersion'] = gameVersion;

    final urls = [_curseforgeMirror, _curseforgeApi];
    for (final baseUrl in urls) {
      try {
        final uri = Uri.parse('$baseUrl/mods/$projectId/files').replace(queryParameters: params);
        final response = await http.get(uri, headers: _curseforgeHeaders(baseUrl))
            .timeout(Duration(seconds: baseUrl == _curseforgeMirror ? 10 : 15));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final files = data['data'] as List;
          return files.map((f) => ResourceVersion.fromCurseforge(f)).toList();
        }
      } catch (e) {
        debugLog('[ResourceDownload] Failed to get CF versions from $baseUrl: $e');
      }
    }
    return [];
  }

  Future<bool> downloadResource(ResourceVersion version, String destPath, {
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  }) async {
    if (version.files.isEmpty) return false;
    final file = version.files.first;
    final fileName = destPath.split('/').last.split('\\').last;

    return await _downloadService.downloadFilesInBackground(
      '资源: $fileName',
      [DownloadFile(
        url: file.url,
        path: destPath,
        sha1: file.hashes['sha1'],
        size: file.size,
      )],
      1,
      onProgress: onProgress,
      onStatus: onStatus,
    );
  }

  Future<bool> downloadMultipleResources(
    List<({ResourceVersion version, String destPath})> items, {
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  }) async {
    if (items.isEmpty) return true;

    final files = <DownloadFile>[];
    for (final item in items) {
      if (item.version.files.isEmpty) continue;
      final file = item.version.files.first;
      files.add(DownloadFile(
        url: file.url,
        path: item.destPath,
        sha1: file.hashes['sha1'],
        size: file.size,
      ));
    }

    if (files.isEmpty) return true;

    return await _downloadService.downloadFilesInBackground(
      '批量下载 (${files.length} 个文件)',
      files,
      4,
      onProgress: onProgress,
      onStatus: onStatus,
    );
  }

  Future<void> loadCategories(ResourceType type) async {
    final urls = [_modrinthMirror, _modrinthApi];
    for (final baseUrl in urls) {
      try {
        final response = await http.get(
          Uri.parse('$baseUrl/tag/category'),
          headers: _modrinthHeaders,
        ).timeout(Duration(seconds: baseUrl == _modrinthMirror ? 10 : 15));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as List;
          final projectType = _getModrinthProjectType(type);
          _categories = data
              .where((c) => c['project_type'] == projectType)
              .map((c) => ResourceCategory(id: c['name'], name: c['name'], icon: c['icon']))
              .toList();
          notifyListeners();
          return;
        }
      } catch (e) {
        debugLog('[ResourceDownload] Failed to load categories: $e');
      }
    }
  }

  Map<String, String> get _modrinthHeaders => {
    'User-Agent': 'OblivionLauncher/1.0.0',
    'Accept': 'application/json',
  };

  Map<String, String> _curseforgeHeaders(String baseUrl) => {
    'Accept': 'application/json',
    'User-Agent': 'OblivionLauncher/1.0.0',
  };

  String _getModrinthProjectType(ResourceType type) => switch (type) {
    ResourceType.mod => 'mod',
    ResourceType.modpack => 'modpack',
    ResourceType.shader => 'shader',
    ResourceType.resourcePack => 'resourcepack',
    ResourceType.world => 'world',
    ResourceType.datapack => 'datapack',
  };

  String _getCurseforgeClassId(ResourceType type) => switch (type) {
    ResourceType.mod => '6',
    ResourceType.modpack => '4471',
    ResourceType.shader => '6552',
    ResourceType.resourcePack => '12',
    ResourceType.world => '17',
    ResourceType.datapack => '6945',
  };

  String _convertSortType(ResourceSortType type) => switch (type) {
    ResourceSortType.relevance => 'relevance',
    ResourceSortType.downloads => 'downloads',
    ResourceSortType.updated => 'updated',
    ResourceSortType.newest => 'newest',
  };

  String _convertCurseforgeSortType(ResourceSortType type) => switch (type) {
    ResourceSortType.relevance => '1',
    ResourceSortType.downloads => '6',
    ResourceSortType.updated => '3',
    ResourceSortType.newest => '3',
  };
}

class ResourceCategory {
  final String id;
  final String name;
  final String? icon;
  ResourceCategory({required this.id, required this.name, this.icon});
}
