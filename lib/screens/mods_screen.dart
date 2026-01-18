import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../services/game_service.dart';
import '../services/mod_service.dart';
import '../services/mod_download_service.dart';
import '../services/config_service.dart';
import '../services/debug_logger.dart';
import '../models/mod_info.dart';
import '../models/remote_mod.dart';
import '../l10n/app_localizations.dart';

class ModsScreen extends StatefulWidget {
  const ModsScreen({super.key});

  @override
  State<ModsScreen> createState() => _ModsScreenState();
}

class _ModsScreenState extends State<ModsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ModService _modService;
  bool _initialized = false;
  
  final _searchController = TextEditingController();
  String? _selectedCategory;
  ModLoaderFilter? _selectedLoader;
  ModSortType _sortType = ModSortType.downloads;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final config = context.read<ConfigService>();
      _modService = ModService(config.gameDirectory);
      _loadMods();
      
      
      final modDownloadService = context.read<ModDownloadService>();
      modDownloadService.loadModrinthCategories();
      modDownloadService.loadPopularMods();
      
      _initialized = true;
    }
  }

  Future<void> _loadMods() async {
    final gameService = context.read<GameService>();
    await _modService.loadMods(gameService.selectedVersion);
    if (mounted) setState(() {});
  }

  Future<void> _searchMods({int page = 0}) async {
    debugLog('[ModsScreen] _searchMods called: page=$page, query="${_searchController.text}", category=$_selectedCategory, loader=$_selectedLoader');
    
    final modDownloadService = context.read<ModDownloadService>();
    
    
    
    debugLog('[ModsScreen] Calling modDownloadService.searchMods with gameVersion=null (user should select manually)');
    
    await modDownloadService.searchMods(
      query: _searchController.text,
      gameVersion: null,  
      category: _selectedCategory,
      loader: _selectedLoader,
      sortType: _sortType,
      page: page,
    );
    
    debugLog('[ModsScreen] searchMods returned. Results: ${modDownloadService.searchResults.length}, Error: "${modDownloadService.searchError}"');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gameService = context.watch<GameService>();
    final selectedVersion = gameService.selectedVersion;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.get('mod_management'), style: Theme.of(context).textTheme.headlineMedium),
                  if (selectedVersion != null)
                    Text('${l10n.get('nav_versions')}: $selectedVersion',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
              Row(
                children: [
                  IconButton(onPressed: _loadMods, icon: const Icon(Icons.refresh), tooltip: l10n.get('refresh')),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _modService.openModsFolder(selectedVersion),
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.get('open_folder')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _addMod,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.get('add_mod')),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            tabs: [Tab(text: l10n.get('installed_mods')), Tab(text: l10n.get('download_mods'))],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildInstalledTab(), _buildDownloadTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstalledTab() {
    return _modService.isLoading
        ? const Center(child: CircularProgressIndicator())
        : _modService.mods.isEmpty
            ? _buildEmptyState()
            : _buildModList();
  }

  Widget _buildDownloadTab() {
    final l10n = AppLocalizations.of(context);
    final modDownloadService = context.watch<ModDownloadService>();
    
    return Column(
      children: [
        
        Row(
          children: [
            SegmentedButton<ModSourceType>(
              segments: [
                ButtonSegment(
                  value: ModSourceType.modrinth,
                  label: Text(l10n.get('mod_source_modrinth')),
                  icon: const Icon(Icons.public),
                ),
                ButtonSegment(
                  value: ModSourceType.curseforge,
                  label: Text(l10n.get('mod_source_curseforge')),
                  icon: const Icon(Icons.local_fire_department),
                ),
              ],
              selected: {modDownloadService.currentSource},
              onSelectionChanged: (selected) async {
                final newSource = selected.first;
                if (newSource == modDownloadService.currentSource) return;
                
                
                modDownloadService.setSource(newSource);
                
                await _searchMods(page: 0);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l10n.get('search_mods'),
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onSubmitted: (_) => _searchMods(),
              ),
            ),
            const SizedBox(width: 12),
            PopupMenuButton<String>(
              icon: const Icon(Icons.category),
              tooltip: l10n.get('cat_all'),
              onSelected: (value) {
                setState(() => _selectedCategory = value == 'all' ? null : value);
                _searchMods();
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'all', child: Text(l10n.get('cat_all'))),
                ...modDownloadService.categories.map((c) => 
                  PopupMenuItem(value: c.id, child: Text(_translateCategory(c.id)))),
              ],
            ),
            PopupMenuButton<ModLoaderFilter?>(
              icon: const Icon(Icons.extension),
              tooltip: l10n.get('mod_loader'),
              onSelected: (value) {
                setState(() => _selectedLoader = value);
                _searchMods();
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: null, child: Text(l10n.get('cat_all'))),
                const PopupMenuItem(value: ModLoaderFilter.fabric, child: Text('Fabric')),
                const PopupMenuItem(value: ModLoaderFilter.forge, child: Text('Forge')),
                const PopupMenuItem(value: ModLoaderFilter.quilt, child: Text('Quilt')),
                const PopupMenuItem(value: ModLoaderFilter.neoforge, child: Text('NeoForge')),
              ],
            ),
            PopupMenuButton<ModSortType>(
              icon: const Icon(Icons.sort),
              onSelected: (value) {
                setState(() => _sortType = value);
                _searchMods();
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: ModSortType.relevance, child: Text(l10n.get('sort_relevance'))),
                PopupMenuItem(value: ModSortType.downloads, child: Text(l10n.get('sort_downloads'))),
                PopupMenuItem(value: ModSortType.updated, child: Text(l10n.get('sort_updated'))),
                PopupMenuItem(value: ModSortType.newest, child: Text(l10n.get('sort_newest'))),
              ],
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => _searchMods(), child: Text(l10n.get('search'))),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: modDownloadService.isSearching
              ? const Center(child: CircularProgressIndicator())
              : modDownloadService.searchError.isNotEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
                          const SizedBox(height: 16),
                          Text('${l10n.get('error')}: ${modDownloadService.searchError}',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.tonal(
                            onPressed: () => _searchMods(),
                            child: Text(l10n.get('retry')),
                          ),
                        ],
                      ),
                    )
                  : modDownloadService.searchResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search, size: 64, color: Theme.of(context).colorScheme.outline),
                              const SizedBox(height: 16),
                              Text(
                                modDownloadService.hasSearched 
                                    ? l10n.get('no_results')
                                    : l10n.get('enter_keyword'),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              if (!modDownloadService.hasSearched)
                                FilledButton.tonal(
                                  onPressed: () => _searchMods(),
                                  child: Text(l10n.get('load_popular')),
                                ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            Expanded(child: _buildSearchResults(modDownloadService)),
                            if (modDownloadService.totalPages > 1) _buildPagination(modDownloadService),
                          ],
                        ),
        ),
      ],
    );
  }

  String _translateCategory(String category) {
    final l10n = AppLocalizations.of(context);
    return l10n.get('cat_$category');
  }

  Widget _buildPagination(ModDownloadService service) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: service.currentPage > 0 
                ? () => _searchMods(page: service.currentPage - 1) 
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          const SizedBox(width: 16),
          Text('${l10n.get('page')} ${service.currentPage + 1} / ${service.totalPages}'),
          const SizedBox(width: 16),
          IconButton(
            onPressed: service.currentPage < service.totalPages - 1 
                ? () => _searchMods(page: service.currentPage + 1) 
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ModDownloadService service) {
    return ListView.builder(
      itemCount: service.searchResults.length,
      itemBuilder: (context, index) {
        final mod = service.searchResults[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: mod.iconUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(mod.iconUrl!, width: 48, height: 48, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildModIcon()),
                  )
                : _buildModIcon(),
            title: Text(mod.title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mod.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.download, size: 14, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 4),
                    Text(_formatDownloads(mod.downloads), style: Theme.of(context).textTheme.bodySmall),
                    if (mod.author != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.person, size: 14, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(width: 4),
                      Text(mod.author!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ],
            ),
            trailing: FilledButton.tonal(
              onPressed: () => _showModVersions(mod),
              child: Text(AppLocalizations.of(context).get('download')),
            ),
            onTap: () => _showModDetails(mod),
          ),
        );
      },
    );
  }

  Widget _buildModIcon() {
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.extension),
    );
  }

  void _showModVersions(RemoteMod mod) async {
    final l10n = AppLocalizations.of(context);
    final modDownloadService = context.read<ModDownloadService>();
    
    debugLog('[ModsScreen] _showModVersions: mod=${mod.title}, id=${mod.id}');

    showDialog(
      context: context,
      builder: (context) => _ModVersionsDialog(
        mod: mod,
        modDownloadService: modDownloadService,
        l10n: l10n,
        onDownload: (version) => _downloadModVersion(mod, version),
      ),
    );
  }

  Future<void> _downloadModVersion(RemoteMod mod, ModVersion version) async {
    final l10n = AppLocalizations.of(context);
    final modDownloadService = context.read<ModDownloadService>();
    if (version.files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.get('error'))));
      return;
    }

    Navigator.pop(context);

    final gameService = context.read<GameService>();
    final modsDir = _modService.getModsDir(gameService.selectedVersion);
    final file = version.files.first;
    final destPath = p.join(modsDir, file.filename);

    final success = await modDownloadService.downloadMod(version, destPath,
      onStatus: (status) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status), duration: const Duration(seconds: 1)));
      },
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${mod.title} ${l10n.get('completed')}')));
        _loadMods();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${mod.title} ${l10n.get('failed')}'), backgroundColor: Theme.of(context).colorScheme.error));
      }
    }
  }

  void _showModDetails(RemoteMod mod) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            if (mod.iconUrl != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(mod.iconUrl!, width: 48, height: 48)),
              ),
            Expanded(child: Text(mod.title)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(mod.description),
                const SizedBox(height: 16),
                if (mod.author != null) _detailRow(context, l10n.get('author'), mod.author!),
                _detailRow(context, l10n.get('download'), _formatDownloads(mod.downloads)),
                if (mod.categories.isNotEmpty) _detailRow(context, l10n.get('cat_all'), mod.categories.map(_translateCategory).join(', ')),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () { Navigator.pop(context); _showModVersions(mod); },
            child: Text(l10n.get('download')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension_off, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(l10n.get('no_mods'), style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _buildModList() {
    return ListView.builder(
      itemCount: _modService.mods.length,
      itemBuilder: (context, index) {
        final mod = _modService.mods[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: mod.enabled
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(Icons.extension, color: mod.enabled ? Theme.of(context).colorScheme.onPrimaryContainer : null),
            ),
            title: Text(mod.displayName),
            subtitle: Text([
              if (mod.version != null) 'v${mod.version}',
              if (mod.authors.isNotEmpty) mod.authors.join(', '),
              _formatBytes(mod.fileSize),
              mod.loaderType.name,
            ].where((s) => s.isNotEmpty).join(' - ')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(value: mod.enabled, onChanged: (value) async { await _modService.toggleMod(mod); setState(() {}); }),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteMod(mod)),
              ],
            ),
            onTap: () => _showLocalModDetails(mod),
          ),
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _formatDownloads(int downloads) {
    if (downloads < 1000) return '$downloads';
    if (downloads < 1000000) return '${(downloads / 1000).toStringAsFixed(1)}K';
    return '${(downloads / 1000000).toStringAsFixed(1)}M';
  }

  Future<void> _addMod() async {
    final gameService = context.read<GameService>();
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['jar'], allowMultiple: true);
    if (result != null && mounted) {
      for (final file in result.files) {
        if (file.path != null) await _modService.addMod(file.path!, gameService.selectedVersion);
      }
      setState(() {});
    }
  }

  void _deleteMod(LocalMod mod) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.get('delete')),
        content: Text('${mod.displayName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(l10n.get('cancel'))),
          FilledButton(onPressed: () async { 
            await _modService.deleteMod(mod); 
            if (dialogContext.mounted) {
              Navigator.pop(dialogContext); 
              setState(() {}); 
            }
          }, child: Text(l10n.get('delete'))),
        ],
      ),
    );
  }

  void _showLocalModDetails(LocalMod mod) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(mod.displayName),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (mod.modId != null) _detailRow(context, 'Mod ID', mod.modId!),
              if (mod.version != null) _detailRow(context, l10n.get('version'), mod.version!),
              if (mod.authors.isNotEmpty) _detailRow(context, l10n.get('author'), mod.authors.join(', ')),
              _detailRow(context, l10n.get('mod_loader'), mod.loaderType.name),
              if (mod.description != null) ...[
                const SizedBox(height: 16),
                Text(mod.description!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.get('close')))],
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
}

class _ModVersionsDialog extends StatefulWidget {
  final RemoteMod mod;
  final ModDownloadService modDownloadService;
  final AppLocalizations l10n;
  final void Function(ModVersion) onDownload;

  const _ModVersionsDialog({
    required this.mod,
    required this.modDownloadService,
    required this.l10n,
    required this.onDownload,
  });

  @override
  State<_ModVersionsDialog> createState() => _ModVersionsDialogState();
}

class _ModVersionsDialogState extends State<_ModVersionsDialog> {
  final _searchController = TextEditingController();
  List<ModVersion> _allVersions = [];
  List<ModVersion> _filteredVersions = [];
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
      final versions = await widget.modDownloadService.getModVersions(widget.mod.id);
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
    return AlertDialog(
      title: Text('${widget.l10n.get('select_version_download')} - ${widget.mod.title}'),
      content: SizedBox(
        width: 550,
        height: 450,
        child: Column(
          children: [
            
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: widget.l10n.get('search_version_hint'),
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
                      ? Center(child: Text('${widget.l10n.get('error')}: $_error'))
                      : _filteredVersions.isEmpty
                          ? Center(child: Text(_allVersions.isEmpty 
                              ? widget.l10n.get('no_compatible_version')
                              : widget.l10n.get('no_results')))
                          : ListView.builder(
                              itemCount: _filteredVersions.length,
                              itemBuilder: (context, index) {
                                final v = _filteredVersions[index];
                                return ListTile(
                                  title: Text(v.name),
                                  subtitle: Text(
                                    [v.versionNumber, v.gameVersions.take(3).join(', '), v.loaders.join(', ')]
                                        .where((s) => s.isNotEmpty)
                                        .join(' - '),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildVersionTypeChip(v.versionType),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.download),
                                        onPressed: () => widget.onDownload(v),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        Text('${_filteredVersions.length} / ${_allVersions.length}', 
            style: Theme.of(context).textTheme.bodySmall),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.l10n.get('close')),
        ),
      ],
    );
  }

  Widget _buildVersionTypeChip(ModVersionType type) {
    final (label, color) = switch (type) {
      ModVersionType.release => (widget.l10n.get('version_release'), Colors.green),
      ModVersionType.beta => (widget.l10n.get('version_beta'), Colors.orange),
      ModVersionType.alpha => (widget.l10n.get('version_alpha'), Colors.red),
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
