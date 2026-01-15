import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../services/resource_download_service.dart';
import '../services/favorites_service.dart';
import '../services/game_service.dart';
import '../services/download_service.dart';
import '../services/modpack_install_service.dart';
import '../models/resource_item.dart';
import '../models/game_version.dart';
import '../models/config.dart';
import '../models/download_task.dart';
import '../l10n/app_localizations.dart';
import '../services/debug_logger.dart';
import 'downloads_screen.dart';

class DownloadCenterScreen extends StatefulWidget {
  const DownloadCenterScreen({super.key});

  @override
  State<DownloadCenterScreen> createState() => _DownloadCenterScreenState();
}

class _DownloadCenterScreenState extends State<DownloadCenterScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String? _selectedCategory;
  String? _selectedLoader;
  ResourceSortType _sortType = ResourceSortType.downloads;
  final Set<String> _selectedItems = {};
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this); // 增加到8个标签
    _tabController.addListener(_onTabChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final service = context.read<ResourceDownloadService>();
      service.setType(ResourceType.mod);
      service.loadCategories(ResourceType.mod);
      _searchResources();
      
      final favService = context.read<FavoritesService>();
      favService.load();
      
      final gameService = context.read<GameService>();
      gameService.refreshVersions();
      
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      final currentIndex = _tabController.index;
      final type = _getTypeFromIndex(currentIndex);
      if (type != null) {
        final service = context.read<ResourceDownloadService>();
        
        // 世界类型只支持 CurseForge，自动切换
        if (type == ResourceType.world && service.currentSource == ResourceSource.modrinth) {
          service.setSource(ResourceSource.curseforge);
        }
        
        service.setType(type);
        service.loadCategories(type);
        _selectedItems.clear();
        _searchController.clear();
        _selectedCategory = null;
        _selectedLoader = null;
        
        // 使用当前 index 来防止快速切换时的数据串扰
        final searchIndex = currentIndex;
        _searchResources().then((_) {
          // 如果在搜索完成后 tab 已经切换，忽略结果
          if (_tabController.index != searchIndex) return;
          if (mounted) setState(() {});
        });
      } else {
        setState(() {});
      }
    }
  }

  ResourceType? _getTypeFromIndex(int index) {
    return switch (index) {
      0 => ResourceType.mod,
      1 => ResourceType.modpack,
      2 => ResourceType.shader,
      3 => ResourceType.resourcePack,
      4 => ResourceType.world,
      5 => ResourceType.datapack,
      6 => null, // 收藏
      7 => null, // 版本下载
      _ => null,
    };
  }

  Future<void> _searchResources({int page = 0}) async {
    final service = context.read<ResourceDownloadService>();
    await service.searchResources(
      query: _searchController.text,
      category: _selectedCategory,
      loader: _selectedLoader,
      sortType: _sortType,
      page: page,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final downloadService = context.watch<DownloadService>();
    final hasActiveDownloads = downloadService.groups.any(
      (g) => g.status == DownloadStatus.downloading
    );
    
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.get('nav_downloads'), style: Theme.of(context).textTheme.headlineMedium),
              ),
              // 下载列表按钮
              Badge(
                isLabelVisible: hasActiveDownloads,
                label: Text('${downloadService.groups.where((g) => g.status == DownloadStatus.downloading).length}'),
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                    );
                  },
                  icon: hasActiveDownloads 
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_done),
                  label: Text(l10n.get('download_management')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // MD3风格的标签栏
          _buildTabBar(l10n),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildResourceTab(ResourceType.mod),
                _buildResourceTab(ResourceType.modpack),
                _buildResourceTab(ResourceType.shader),
                _buildResourceTab(ResourceType.resourcePack),
                _buildResourceTab(ResourceType.world),
                _buildResourceTab(ResourceType.datapack),
                _buildFavoritesTab(),
                _buildVersionDownloadTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(AppLocalizations l10n) {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.label,
      labelPadding: const EdgeInsets.symmetric(horizontal: 12),
      tabs: [
        Tab(text: l10n.get('resource_mod')),
        Tab(text: l10n.get('resource_modpack')),
        Tab(text: l10n.get('resource_shader')),
        Tab(text: l10n.get('resource_resourcepack')),
        Tab(text: l10n.get('resource_world')),
        Tab(text: l10n.get('resource_datapack')),
        Tab(text: l10n.get('favorites')),
        Tab(text: l10n.get('nav_versions')),
      ],
    );
  }


  Widget _buildResourceTab(ResourceType type) {
    final l10n = AppLocalizations.of(context);
    final service = context.watch<ResourceDownloadService>();

    
    // 世界类型只显示CurseForge
    final showModrinth = type != ResourceType.world;
    
    return Column(
      children: [
        // 搜索栏和过滤器行
        Row(
          children: [
            // 搜索框
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l10n.get('search_resources'),
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _searchResources(),
              ),
            ),
            const SizedBox(width: 12),
            // 分类过滤
            PopupMenuButton<String>(
              icon: const Icon(Icons.category),
              tooltip: l10n.get('cat_all'),
              onSelected: (value) {
                setState(() => _selectedCategory = value == 'all' ? null : value);
                _searchResources();
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'all', child: Text(l10n.get('cat_all'))),
                ...service.categories.map((c) => 
                  PopupMenuItem(value: c.id, child: Text(_translateCategory(c.id)))),
              ],
            ),
            // 加载器过滤（仅模组和整合包）
            if (type == ResourceType.mod || type == ResourceType.modpack)
              PopupMenuButton<String?>(
                icon: const Icon(Icons.extension),
                tooltip: l10n.get('mod_loader'),
                onSelected: (value) {
                  setState(() => _selectedLoader = value);
                  _searchResources();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: null, child: Text(l10n.get('cat_all'))),
                  const PopupMenuItem(value: 'fabric', child: Text('Fabric')),
                  const PopupMenuItem(value: 'forge', child: Text('Forge')),
                  const PopupMenuItem(value: 'quilt', child: Text('Quilt')),
                  const PopupMenuItem(value: 'neoforge', child: Text('NeoForge')),
                ],
              ),
            // 排序
            PopupMenuButton<ResourceSortType>(
              icon: const Icon(Icons.sort),
              tooltip: l10n.get('sort_downloads'),
              onSelected: (value) {
                setState(() => _sortType = value);
                _searchResources();
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: ResourceSortType.relevance, child: Text(l10n.get('sort_relevance'))),
                PopupMenuItem(value: ResourceSortType.downloads, child: Text(l10n.get('sort_downloads'))),
                PopupMenuItem(value: ResourceSortType.updated, child: Text(l10n.get('sort_updated'))),
                PopupMenuItem(value: ResourceSortType.newest, child: Text(l10n.get('sort_newest'))),
              ],
            ),
            const SizedBox(width: 8),
            // 搜索按钮
            FilledButton.icon(
              onPressed: () => _searchResources(),
              icon: const Icon(Icons.search),
              label: Text(l10n.get('search')),
            ),
            const SizedBox(width: 12),
            // API源选择（放在右侧）
            SegmentedButton<ResourceSource>(
              segments: [
                if (showModrinth)
                  ButtonSegment(
                    value: ResourceSource.modrinth,
                    label: const Text('Modrinth'),
                    icon: const Icon(Icons.public, size: 18),
                  ),
                ButtonSegment(
                  value: ResourceSource.curseforge,
                  label: const Text('CurseForge'),
                  icon: const Icon(Icons.local_fire_department, size: 18),
                ),
              ],
              selected: {service.currentSource},
              onSelectionChanged: (selected) {
                final newSource = selected.first;
                if (newSource == service.currentSource) return;
                service.setSource(newSource);
                _searchResources(page: 0);
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 搜索结果
        Expanded(
          child: service.isSearching
              ? const Center(child: CircularProgressIndicator())
              : service.searchError.isNotEmpty
                  ? _buildErrorView(service.searchError)
                  : service.searchResults.isEmpty
                      ? _buildEmptyView()
                      : Column(
                          children: [
                            Expanded(child: _buildSearchResults(service)),
                            _buildPaginationBar(service),
                          ],
                        ),
        ),
      ],
    );
  }

  Widget _buildSearchResults(ResourceDownloadService service) {
    return ListView.builder(
      itemCount: service.searchResults.length,
      itemBuilder: (context, index) {
        final item = service.searchResults[index];
        return _buildResourceCard(item);
      },
    );
  }

  Widget _buildResourceCard(ResourceItem item, {bool isFavorite = false}) {
    final favService = context.watch<FavoritesService>();
    final isSelected = _selectedItems.contains(item.id);
    final isFav = favService.isFavorite(item.id, item.source);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isFavorite)
              Checkbox(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedItems.add(item.id);
                    } else {
                      _selectedItems.remove(item.id);
                    }
                  });
                },
              ),
            item.iconUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      item.iconUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildResourceIcon(item.type),
                    ),
                  )
                : _buildResourceIcon(item.type),
          ],
        ),
        title: Text(item.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.download, size: 14, color: Theme.of(context).colorScheme.outline),
                const SizedBox(width: 4),
                Text(_formatDownloads(item.downloads), style: Theme.of(context).textTheme.bodySmall),
                if (item.author != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.person, size: 14, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(item.author!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
              color: isFav ? Colors.red : null,
              onPressed: () => favService.toggleFavorite(item),
            ),
            FilledButton.tonal(
              onPressed: () => _showResourceVersions(item),
              child: Text(AppLocalizations.of(context).get('download')),
            ),
          ],
        ),
        onTap: () => _showResourceDetails(item),
      ),
    );
  }

  Widget _buildResourceIcon(ResourceType type) {
    final icon = switch (type) {
      ResourceType.mod => Icons.extension,
      ResourceType.modpack => Icons.inventory_2,
      ResourceType.shader => Icons.wb_sunny,
      ResourceType.resourcePack => Icons.texture,
      ResourceType.world => Icons.public,
      ResourceType.datapack => Icons.data_object,
    };
    
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon),
    );
  }

  // 分页栏（参考模组页面）
  Widget _buildPaginationBar(ResourceDownloadService service) {
    final l10n = AppLocalizations.of(context);
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // 分页控制
          IconButton(
            onPressed: service.currentPage > 0 
                ? () => _searchResources(page: service.currentPage - 1) 
                : null,
            icon: const Icon(Icons.chevron_left),
            tooltip: l10n.get('page'),
          ),
          Text('${l10n.get('page')} ${service.currentPage + 1} / ${service.totalPages}',
            style: Theme.of(context).textTheme.bodyMedium),
          IconButton(
            onPressed: service.currentPage < service.totalPages - 1 
                ? () => _searchResources(page: service.currentPage + 1) 
                : null,
            icon: const Icon(Icons.chevron_right),
            tooltip: l10n.get('page'),
          ),
          const Spacer(),
          // 批量操作指示器（缩小版）
          if (_selectedItems.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 16, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  const SizedBox(width: 6),
                  Text('${_selectedItems.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    )),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => setState(() => _selectedItems.clear()),
              icon: const Icon(Icons.clear),
              iconSize: 20,
              tooltip: l10n.get('clear_selection'),
            ),
            const SizedBox(width: 4),
            FilledButton.tonalIcon(
              onPressed: _batchDownload,
              icon: const Icon(Icons.download, size: 18),
              label: Text(l10n.get('batch_download')),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 36),
              ),
            ),
          ],
        ],
      ),
    );
  }


  Widget _buildErrorView(String error) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text('${l10n.get('error')}: $error',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => _searchResources(),
            child: Text(l10n.get('retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    final l10n = AppLocalizations.of(context);
    final service = context.read<ResourceDownloadService>();
    
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            service.hasSearched 
                ? l10n.get('no_results')
                : l10n.get('enter_keyword'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (!service.hasSearched)
            FilledButton.tonal(
              onPressed: () => _searchResources(),
              child: Text(l10n.get('load_popular')),
            ),
        ],
      ),
    );
  }

  Widget _buildFavoritesTab() {
    final l10n = AppLocalizations.of(context);
    final favService = context.watch<FavoritesService>();
    
    if (!favService.isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final favorites = favService.favorites;
    
    if (favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(l10n.get('no_favorites'), style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final item = favorites[index];
        return _buildResourceCard(item, isFavorite: true);
      },
    );
  }

  // 版本下载标签页
  Widget _buildVersionDownloadTab() {
    final l10n = AppLocalizations.of(context);
    final gameService = context.watch<GameService>();
    
    return Column(
      children: [
        // 过滤器
        Row(
          children: [
            FilterChip(
              label: Text(l10n.get('show_snapshots')),
              selected: gameService.showSnapshots,
              onSelected: (v) => setState(() => gameService.showSnapshots = v),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text(l10n.get('show_old_versions')),
              selected: gameService.showOldVersions,
              onSelected: (v) => setState(() => gameService.showOldVersions = v),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => gameService.refreshVersions(),
              icon: gameService.isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : const Icon(Icons.refresh),
              tooltip: l10n.get('refresh'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(child: _buildVersionList(gameService)),
      ],
    );
  }

  Widget _buildVersionList(GameService gameService) {
    final l10n = AppLocalizations.of(context);
    final versions = gameService.availableVersions.where((v) {
      if (v.type == 'release') return true;
      if (v.type == 'snapshot' && gameService.showSnapshots) return true;
      if ((v.type == 'old_beta' || v.type == 'old_alpha') && gameService.showOldVersions) return true;
      return false;
    }).toList();

    if (versions.isEmpty) {
      return Center(
        child: gameService.isLoading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, size: 64, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(l10n.get('error')),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () => gameService.refreshVersions(),
                    child: Text(l10n.get('retry')),
                  ),
                ],
              ),
      );
    }

    return ListView.builder(
      itemCount: versions.length,
      itemBuilder: (context, index) {
        final version = versions[index];
        final isInstalled = gameService.installedVersions.any(
          (v) => v.id == version.id || v.inheritsFrom == version.id
        );
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getVersionIcon(version.versionType),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            title: Text(version.id),
            subtitle: Text(
              '${_getVersionTypeName(version.versionType)} • ${_formatDate(version.releaseTime)}',
            ),
            trailing: isInstalled
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.get('installed'),
                      style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                  )
                : FilledButton.tonal(
                    onPressed: () => _showInstallDialog(version),
                    child: Text(l10n.get('install')),
                  ),
          ),
        );
      },
    );
  }

  IconData _getVersionIcon(VersionType type) => switch (type) {
    VersionType.release => Icons.check_circle,
    VersionType.snapshot => Icons.science,
    VersionType.oldBeta => Icons.history,
    VersionType.oldAlpha => Icons.history_toggle_off,
  };

  String _getVersionTypeName(VersionType type) {
    final l10n = AppLocalizations.of(context);
    return switch (type) {
      VersionType.release => l10n.get('type_release'),
      VersionType.snapshot => l10n.get('type_snapshot'),
      VersionType.oldBeta => l10n.get('type_old_beta'),
      VersionType.oldAlpha => l10n.get('type_old_alpha'),
    };
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  void _showInstallDialog(GameVersion version) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _InstallVersionDialog(version: version),
    );
  }


  void _showResourceVersions(ResourceItem item) async {
    final service = context.read<ResourceDownloadService>();
    
    debugLog('[DownloadCenter] _showResourceVersions: item=${item.title}, id=${item.id}');

    showDialog(
      context: context,
      builder: (context) => _ResourceVersionsDialog(
        item: item,
        service: service,
        onDownload: (version) => _downloadResource(item, version),
      ),
    );
  }

  Future<void> _downloadResource(ResourceItem item, ResourceVersion version) async {
    final service = context.read<ResourceDownloadService>();
    
    if (version.files.isEmpty) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.get('error'))),
        );
      }
      return;
    }

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    
    // 如果是整合包，显示安装对话框
    if (item.type == ResourceType.modpack) {
      Navigator.pop(context); // 关闭版本选择对话框
      _showModpackInstallDialog(item, version);
      return;
    }
    
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: l10n.get('select_download_location'),
    );
    
    if (result == null || !mounted) return;

    Navigator.pop(context);

    final fileName = version.files.first.filename;
    final destPath = p.join(result, fileName);

    final success = await service.downloadResource(
      version,
      destPath,
      onStatus: (status) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(status), duration: const Duration(seconds: 1)),
          );
        }
      },
    );

    if (mounted) {
      final l10nFinal = AppLocalizations.of(context);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.title} ${l10nFinal.get('completed')}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${item.title} ${l10nFinal.get('failed')}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _batchDownload() async {
    final l10n = AppLocalizations.of(context);
    final service = context.read<ResourceDownloadService>();
    
    if (_selectedItems.isEmpty) return;

    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: l10n.get('select_download_location'),
    );
    
    if (result == null) return;

    final items = service.searchResults
        .where((item) => _selectedItems.contains(item.id))
        .toList();

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BatchDownloadDialog(
        items: items,
        service: service,
        destDir: result,
      ),
    );
  }

  void _showModpackInstallDialog(ResourceItem item, ResourceVersion version) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ModpackInstallDialog(
        item: item,
        version: version,
      ),
    );
  }

  void _showResourceDetails(ResourceItem item) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            if (item.iconUrl != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(item.iconUrl!, width: 48, height: 48),
                ),
              ),
            Expanded(child: Text(item.title)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.description),
                const SizedBox(height: 16),
                if (item.author != null) _detailRow(context, l10n.get('author'), item.author!),
                _detailRow(context, l10n.get('download'), _formatDownloads(item.downloads)),
                if (item.categories.isNotEmpty) 
                  _detailRow(context, l10n.get('cat_all'), item.categories.map(_translateCategory).join(', ')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.get('close')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _showResourceVersions(item);
            },
            child: Text(l10n.get('download')),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatDownloads(int downloads) {
    if (downloads < 1000) return '$downloads';
    if (downloads < 1000000) return '${(downloads / 1000).toStringAsFixed(1)}K';
    return '${(downloads / 1000000).toStringAsFixed(1)}M';
  }

  String _translateCategory(String category) {
    final l10n = AppLocalizations.of(context);
    return l10n.get('cat_$category');
  }
}


// 资源版本选择对话框
class _ResourceVersionsDialog extends StatefulWidget {
  final ResourceItem item;
  final ResourceDownloadService service;
  final void Function(ResourceVersion) onDownload;

  const _ResourceVersionsDialog({
    required this.item,
    required this.service,
    required this.onDownload,
  });

  @override
  State<_ResourceVersionsDialog> createState() => _ResourceVersionsDialogState();
}

class _ResourceVersionsDialogState extends State<_ResourceVersionsDialog> {
  final _searchController = TextEditingController();
  List<ResourceVersion> _allVersions = [];
  List<ResourceVersion> _filteredVersions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVersions() async {
    try {
      // 使用资源项本身的 source，而不是当前选中的 source
      final versions = await widget.service.getResourceVersions(
        widget.item.id,
        source: widget.item.source,
      );
      if (mounted) {
        setState(() {
          _allVersions = versions;
          _filteredVersions = versions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _filterVersions(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) {
        _filteredVersions = _allVersions;
      } else {
        _filteredVersions = _allVersions.where((v) {
          return v.name.toLowerCase().contains(q) ||
              v.versionNumber.toLowerCase().contains(q) ||
              v.gameVersions.any((gv) => gv.toLowerCase().contains(q)) ||
              v.loaders.any((l) => l.toLowerCase().contains(q));
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text('${l10n.get('select_version_download')} - ${widget.item.title}'),
      content: SizedBox(
        width: 550,
        height: 450,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.get('search_version_hint'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              onChanged: _filterVersions,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text('${l10n.get('error')}: $_error'))
                      : _filteredVersions.isEmpty
                          ? Center(child: Text(_allVersions.isEmpty 
                              ? l10n.get('no_compatible_version')
                              : l10n.get('no_results')))
                          : ListView.builder(
                              itemCount: _filteredVersions.length,
                              itemBuilder: (context, index) {
                                final v = _filteredVersions[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    title: Text(v.name),
                                    subtitle: Text(
                                      [
                                        v.versionNumber,
                                        v.gameVersions.take(3).join(', '),
                                        v.loaders.join(', ')
                                      ].where((s) => s.isNotEmpty).join(' - '),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildVersionTypeChip(v.versionType, l10n),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.download),
                                          onPressed: () => widget.onDownload(v),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.get('close')),
        ),
      ],
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    );
  }

  Widget _buildVersionTypeChip(ResourceVersionType type, AppLocalizations l10n) {
    final (label, color) = switch (type) {
      ResourceVersionType.release => (l10n.get('version_release'), Colors.green),
      ResourceVersionType.beta => (l10n.get('version_beta'), Colors.orange),
      ResourceVersionType.alpha => (l10n.get('version_alpha'), Colors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}


// 批量下载对话框
class _BatchDownloadDialog extends StatefulWidget {
  final List<ResourceItem> items;
  final ResourceDownloadService service;
  final String destDir;

  const _BatchDownloadDialog({
    required this.items,
    required this.service,
    required this.destDir,
  });

  @override
  State<_BatchDownloadDialog> createState() => _BatchDownloadDialogState();
}

class _BatchDownloadDialogState extends State<_BatchDownloadDialog> {
  final Map<String, ResourceVersion?> _selectedVersions = {};
  final Map<String, List<ResourceVersion>> _availableVersions = {};
  final Map<String, bool> _loadingVersions = {};
  bool _downloading = false;
  int _completed = 0;

  @override
  void initState() {
    super.initState();
    _loadAllVersions();
  }

  Future<void> _loadAllVersions() async {
    for (final item in widget.items) {
      setState(() => _loadingVersions[item.id] = true);
      try {
        // 使用资源项本身的 source，而不是当前选中的 source
        final versions = await widget.service.getResourceVersions(
          item.id,
          source: item.source,
        );
        if (mounted) {
          setState(() {
            _availableVersions[item.id] = versions;
            if (versions.isNotEmpty) {
              _selectedVersions[item.id] = versions.first;
            }
            _loadingVersions[item.id] = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _loadingVersions[item.id] = false);
        }
        debugLog('[BatchDownload] Failed to load versions for ${item.title}: $e');
      }
    }
  }


  Future<void> _startBatchDownload() async {
    setState(() {
      _downloading = true;
      _completed = 0;
    });

    final downloadItems = <({ResourceVersion version, String destPath})>[];
    
    for (final item in widget.items) {
      final version = _selectedVersions[item.id];
      if (version != null && version.files.isNotEmpty) {
        final fileName = version.files.first.filename;
        final destPath = p.join(widget.destDir, fileName);
        downloadItems.add((version: version, destPath: destPath));
      }
    }

    if (downloadItems.isEmpty) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid versions selected')),
        );
      }
      return;
    }

    final success = await widget.service.downloadMultipleResources(
      downloadItems,
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _completed = (progress * downloadItems.length).round();
          });
        }
      },
    );

    if (mounted) {
      Navigator.pop(context);
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success 
              ? l10n.get('batch_download_success')
              : l10n.get('batch_download_failed')),
          backgroundColor: success ? null : Theme.of(context).colorScheme.error,
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allLoaded = _loadingVersions.values.every((loading) => !loading);

    return AlertDialog(
      title: Text(l10n.get('batch_download')),
      content: SizedBox(
        width: 600,
        height: 400,
        child: _downloading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('${l10n.get('downloading')}: $_completed / ${widget.items.length}'),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: widget.items.length,
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  final versions = _availableVersions[item.id] ?? [];
                  final selectedVersion = _selectedVersions[item.id];
                  final isLoading = _loadingVersions[item.id] ?? false;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: item.iconUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(item.iconUrl!, width: 40, height: 40),
                            )
                          : const Icon(Icons.extension),
                      title: Text(item.title),
                      subtitle: isLoading
                          ? Text(l10n.get('loading'))
                          : versions.isEmpty
                              ? Text(l10n.get('no_compatible_version'))
                              : DropdownButton<ResourceVersion>(
                                  value: selectedVersion,
                                  isExpanded: true,
                                  items: versions.map((v) {
                                    return DropdownMenuItem(
                                      value: v,
                                      child: Text(
                                        '${v.name} - ${v.gameVersions.take(2).join(', ')}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (version) {
                                    setState(() => _selectedVersions[item.id] = version);
                                  },
                                ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.pop(context),
          child: Text(l10n.get('cancel')),
        ),
        FilledButton(
          onPressed: _downloading || !allLoaded ? null : _startBatchDownload,
          child: Text(l10n.get('download')),
        ),
      ],
    );
  }
}


// 版本安装对话框
class _InstallVersionDialog extends StatefulWidget {
  final GameVersion version;
  const _InstallVersionDialog({required this.version});

  @override
  State<_InstallVersionDialog> createState() => _InstallVersionDialogState();
}

class _InstallVersionDialogState extends State<_InstallVersionDialog> {
  bool _isLoading = false;
  bool _isInstalling = false;
  String _status = '';
  double _progress = 0;

  final _nameController = TextEditingController();
  String? _selectedFabric;
  String? _selectedForge;
  String? _selectedQuilt;
  IsolationType _isolation = IsolationType.none;

  List<ModLoaderVersion> _fabricVersions = [];
  List<ModLoaderVersion> _forgeVersions = [];
  List<ModLoaderVersion> _quiltVersions = [];

  int _selectedLoader = 0;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.version.id;
    _loadModLoaderVersions();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadModLoaderVersions() async {
    setState(() => _isLoading = true);
    final gameService = context.read<GameService>();
    
    final results = await Future.wait([
      gameService.getFabricVersions(widget.version.id),
      gameService.getForgeVersions(widget.version.id),
      gameService.getQuiltVersions(widget.version.id),
    ]);

    setState(() {
      _fabricVersions = results[0];
      _forgeVersions = results[1];
      _quiltVersions = results[2];
      _isLoading = false;
    });
  }


  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text('${l10n.get('install')} ${widget.version.id}'),
      content: SizedBox(width: 500, child: _isInstalling ? _buildInstallingView() : _buildOptionsView()),
      actions: _isInstalling ? null : [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.get('cancel'))),
        FilledButton(onPressed: _install, child: Text(l10n.get('install'))),
      ],
    );
  }

  Widget _buildInstallingView() {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 16),
            Text(_status, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsView() {
    final l10n = AppLocalizations.of(context);
    if (_isLoading) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(labelText: l10n.get('version_name')),
          ),
          const SizedBox(height: 16),
          Text(l10n.get('version_isolation'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<IsolationType>(
            segments: [
              ButtonSegment(value: IsolationType.none, label: Text(l10n.get('isolation_none'))),
              ButtonSegment(value: IsolationType.partial, label: Text(l10n.get('isolation_partial'))),
              ButtonSegment(value: IsolationType.full, label: Text(l10n.get('isolation_full'))),
            ],
            selected: {_isolation},
            onSelectionChanged: (s) => setState(() => _isolation = s.first),
          ),
          const SizedBox(height: 16),
          Text(l10n.get('mod_loader'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [
              const ButtonSegment(value: 0, label: Text('无')),
              ButtonSegment(value: 1, label: const Text('Fabric'), enabled: _fabricVersions.isNotEmpty),
              ButtonSegment(value: 2, label: const Text('Forge'), enabled: _forgeVersions.isNotEmpty),
              ButtonSegment(value: 3, label: const Text('Quilt'), enabled: _quiltVersions.isNotEmpty),
            ],
            selected: {_selectedLoader},
            onSelectionChanged: (s) => setState(() {
              _selectedLoader = s.first;
              _updateVersionName();
            }),
          ),
          const SizedBox(height: 16),
          if (_selectedLoader == 1 && _fabricVersions.isNotEmpty)
            _buildLoaderDropdown('Fabric', _fabricVersions, _selectedFabric, (v) {
              setState(() { _selectedFabric = v; _updateVersionName(); });
            }),
          if (_selectedLoader == 2 && _forgeVersions.isNotEmpty)
            _buildLoaderDropdown('Forge', _forgeVersions, _selectedForge, (v) {
              setState(() { _selectedForge = v; _updateVersionName(); });
            }),
          if (_selectedLoader == 3 && _quiltVersions.isNotEmpty)
            _buildLoaderDropdown('Quilt', _quiltVersions, _selectedQuilt, (v) {
              setState(() { _selectedQuilt = v; _updateVersionName(); });
            }),
        ],
      ),
    );
  }

  Widget _buildLoaderDropdown(String name, List<ModLoaderVersion> versions, String? selected, void Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(labelText: '$name 版本'),
      value: selected,
      items: versions.map((v) => DropdownMenuItem(value: v.version, child: Text(v.version))).toList(),
      onChanged: onChanged,
    );
  }

  void _updateVersionName() {
    String name = widget.version.id;
    if (_selectedLoader == 1 && _selectedFabric != null) {
      name = '$name-fabric-$_selectedFabric';
    } else if (_selectedLoader == 2 && _selectedForge != null) {
      name = '$name-forge-$_selectedForge';
    } else if (_selectedLoader == 3 && _selectedQuilt != null) {
      name = '$name-quilt-$_selectedQuilt';
    }
    _nameController.text = name;
  }

  Future<void> _install() async {
    setState(() {
      _isInstalling = true;
      _status = '准备安装...';
      _progress = 0;
    });

    final gameService = context.read<GameService>();
    
    try {
      await gameService.installVersion(
        widget.version,
        customName: _nameController.text,
        isolation: _isolation,
        fabric: _selectedLoader == 1 ? _selectedFabric : null,
        forge: _selectedLoader == 2 ? _selectedForge : null,
        quilt: _selectedLoader == 3 ? _selectedQuilt : null,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _progress = progress;
            });
          }
        },
        onStatus: (status) {
          if (mounted) {
            setState(() {
              _status = status;
            });
          }
        },
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_nameController.text} 安装完成')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInstalling = false;
          _status = '安装失败: $e';
        });
      }
    }
  }
}


// 整合包安装对话框
class _ModpackInstallDialog extends StatefulWidget {
  final ResourceItem item;
  final ResourceVersion version;

  const _ModpackInstallDialog({
    required this.item,
    required this.version,
  });

  @override
  State<_ModpackInstallDialog> createState() => _ModpackInstallDialogState();
}

class _ModpackInstallDialogState extends State<_ModpackInstallDialog> {
  final _nameController = TextEditingController();
  bool _isInstalling = false;
  String _status = '';
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    // 使用整合包名称作为默认实例名
    _nameController.text = _sanitizeInstanceName(widget.item.title);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _sanitizeInstanceName(String name) {
    // 移除不允许的字符
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _install() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入实例名称')),
      );
      return;
    }

    setState(() {
      _isInstalling = true;
      _status = '正在准备安装...';
      _progress = 0;
    });

    final modpackService = context.read<ModpackInstallService>();

    try {
      final success = await modpackService.installFromResource(
        widget.item,
        widget.version,
        instanceName: _nameController.text.trim(),
        onStatus: (status) {
          if (mounted) {
            setState(() => _status = status);
          }
        },
        onProgress: (progress) {
          if (mounted) {
            setState(() => _progress = progress);
          }
        },
      );

      if (mounted) {
        Navigator.pop(context);
        final l10n = AppLocalizations.of(context);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${_nameController.text} ${l10n.get('completed')}')),
          );
        } else {
          // 安装失败时自动导出日志
          _exportLogs();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_nameController.text} ${l10n.get('failed')} - 日志已导出到D盘'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      debugLog('[ModpackInstallDialog] 安装异常: $e');
      if (mounted) {
        setState(() {
          _isInstalling = false;
          _status = '安装失败: $e';
        });
        // 导出日志
        _exportLogs();
      }
    }
  }

  Future<void> _exportLogs() async {
    try {
      final path = await DebugLogger().exportLogs(directory: 'D:');
      debugLog('[ModpackInstallDialog] 日志已导出到: $path');
    } catch (e) {
      debugLog('[ModpackInstallDialog] 导出日志失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    
    return AlertDialog(
      title: Text(l10n.get('install_modpack')),
      content: SizedBox(
        width: 450,
        child: _isInstalling ? _buildInstallingView() : _buildOptionsView(),
      ),
      actions: _isInstalling 
          ? [
              TextButton(
                onPressed: _exportLogs,
                child: const Text('导出日志'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.get('cancel')),
              ),
              FilledButton(
                onPressed: _install,
                child: Text(l10n.get('install')),
              ),
            ],
    );
  }

  Widget _buildInstallingView() {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 16),
            Text(_status, textAlign: TextAlign.center),
            if (_progress > 0) ...[
              const SizedBox(height: 8),
              Text('${(_progress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsView() {
    final l10n = AppLocalizations.of(context);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 整合包信息
        Row(
          children: [
            if (widget.item.iconUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  widget.item.iconUrl!,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.inventory_2),
                  ),
                ),
              )
            else
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.inventory_2),
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.item.title,
                    style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(widget.version.name,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    )),
                  if (widget.version.gameVersions.isNotEmpty)
                    Text('MC ${widget.version.gameVersions.first}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      )),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // 实例名称
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: l10n.get('instance_name'),
            hintText: l10n.get('enter_instance_name'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        // 提示信息
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, 
                size: 20, 
                color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.get('modpack_install_hint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
