import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:window_manager/window_manager.dart';
import '../services/resource_service.dart';
import '../services/game_service.dart';
import '../services/config_service.dart';
import '../models/game_version.dart';
import '../models/config.dart';
import '../l10n/app_localizations.dart';
import 'datapack_management_screen.dart';

class VersionResourcesScreen extends StatefulWidget {
  final InstalledVersion version;

  const VersionResourcesScreen({super.key, required this.version});

  @override
  State<VersionResourcesScreen> createState() => _VersionResourcesScreenState();
}

class _VersionResourcesScreenState extends State<VersionResourcesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = ['模组', '资源包', '光影包', '地图'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadResources();
    });
  }

  void _loadResources() {
    final gameService = context.read<GameService>();
    final runDir = gameService.getRunDirectory(widget.version.id);
    context.read<ResourceService>().loadResources(runDir);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resourceService = context.watch<ResourceService>();
    final configService = context.watch<ConfigService>();
    final settings = configService.settings;
    final colorScheme = Theme.of(context).colorScheme;

    final hasCustomBackground = settings.backgroundType != BackgroundType.none;
    final backgroundColor = hasCustomBackground 
        ? colorScheme.surface.withValues(alpha: 0.85)
        : null;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (details) => windowManager.startDragging(),
        ),
        title: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (details) {
            windowManager.startDragging();
          },
          child: Container(
            width: double.infinity,
            color: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('资源管理', style: TextStyle(fontSize: 16)),
                Text(widget.version.id, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
          isScrollable: false,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadResources(),
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: () => _openCurrentFolder(resourceService),
            tooltip: '打开文件夹',
          ),
        ],
      ),
      body: DropTarget(
        onDragDone: (details) => _handleDrop(details, resourceService),
        onDragEntered: (details) {},
        onDragExited: (details) {},
        child: resourceService.isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildResourceList(resourceService.mods, ResourceType.mod, resourceService),
                  _buildResourceList(resourceService.resourcePacks, ResourceType.resourcePack, resourceService),
                  _buildResourceList(resourceService.shaderPacks, ResourceType.shaderPack, resourceService),
                  _buildResourceList(resourceService.saves, ResourceType.save, resourceService),
                ],
              ),
      ),
    );
  }

  void _openCurrentFolder(ResourceService service) {
    ResourceType type;
    switch (_tabController.index) {
      case 0: type = ResourceType.mod; break;
      case 1: type = ResourceType.resourcePack; break;
      case 2: type = ResourceType.shaderPack; break;
      case 3: type = ResourceType.save; break;
      default: return;
    }
    service.openDirectory(type);
  }

  void _handleDrop(DropDoneDetails details, ResourceService service) {
    if (details.files.isEmpty) return;

    ResourceType type;
    switch (_tabController.index) {
      case 0: type = ResourceType.mod; break;
      case 1: type = ResourceType.resourcePack; break;
      case 2: type = ResourceType.shaderPack; break;
      case 3: type = ResourceType.save; break;
      default: return;
    }

    final paths = details.files.map((f) => f.path).toList();
    service.importFiles(paths, type);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在导入 ${paths.length} 个文件...')),
    );
  }

  Widget _buildResourceList(List<ResourceFile> files, ResourceType type, ResourceService service) {
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 64, color: Theme.of(context).colorScheme.outline.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text('暂无文件', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('拖入文件以添加', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        return Card(
          child: ListTile(
            leading: _buildFileIcon(file, type),
            title: Text(file.name),
            subtitle: Text(file.isDirectory ? '文件夹' : _formatSize(file.size)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!file.isDirectory) 
                  Switch(
                    value: file.isEnabled,
                    onChanged: (v) => service.toggleResource(file),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(file, service),
                ),
              ],
            ),
            onTap: type == ResourceType.save ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DataPackManagementScreen(save: file),
                ),
              );
            } : null,
          ),
        );
      },
    );
  }

  Widget _buildFileIcon(ResourceFile file, ResourceType type) {
    IconData icon;
    Color color;

    switch (type) {
      case ResourceType.mod:
        icon = Icons.extension;
        color = Colors.orange;
        break;
      case ResourceType.resourcePack:
        icon = Icons.style;
        color = Colors.blue;
        break;
      case ResourceType.shaderPack:
        icon = Icons.wb_sunny;
        color = Colors.purple;
        break;
      case ResourceType.save:
        icon = Icons.map;
        color = Colors.green;
        break;
      default:
        icon = Icons.insert_drive_file;
        color = Colors.grey;
    }

    if (!file.isEnabled) {
      color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  void _confirmDelete(ResourceFile file, ResourceService service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定要删除 "${file.name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              Navigator.pop(context);
              service.deleteResource(file);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
