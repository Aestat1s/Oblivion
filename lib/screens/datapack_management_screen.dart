import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import '../services/resource_service.dart';

class DataPackManagementScreen extends StatefulWidget {
  final ResourceFile save;

  const DataPackManagementScreen({super.key, required this.save});

  @override
  State<DataPackManagementScreen> createState() => _DataPackManagementScreenState();
}

class _DataPackManagementScreenState extends State<DataPackManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadResources();
    });
  }

  void _loadResources() {
    context.read<ResourceService>().loadDataPacks(widget.save.path);
  }

  @override
  Widget build(BuildContext context) {
    final resourceService = context.watch<ResourceService>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('数据包管理', style: TextStyle(fontSize: 16)),
            Text(widget.save.name, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadResources(),
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: () => _openCurrentFolder(),
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
            : _buildResourceList(resourceService.currentDataPacks, resourceService),
      ),
    );
  }

  void _openCurrentFolder() {
    final path = p.join(widget.save.path, 'datapacks');
    final dir = Directory(path);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    
    if (Platform.isWindows) {
      Process.run('explorer', [path]);
    } else if (Platform.isMacOS) {
      Process.run('open', [path]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [path]);
    }
  }

  void _handleDrop(DropDoneDetails details, ResourceService service) {
    if (details.files.isEmpty) return;
    final paths = details.files.map((f) => f.path).toList();
    service.importDataPacks(paths, widget.save.path);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在导入 ${paths.length} 个文件...')),
    );
  }

  Widget _buildResourceList(List<ResourceFile> files, ResourceService service) {
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 64, color: Theme.of(context).colorScheme.outline.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text('暂无数据包', style: Theme.of(context).textTheme.titleMedium),
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
            leading: _buildFileIcon(file),
            title: Text(file.name),
            subtitle: Text(file.isDirectory ? '文件夹' : _formatSize(file.size)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!file.isDirectory)
                  Switch(
                    value: file.isEnabled,
                    onChanged: (v) => service.toggleDataPack(file, widget.save.path),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(file, service),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFileIcon(ResourceFile file) {
    IconData icon = Icons.data_object;
    Color color = Colors.teal;

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
              service.deleteDataPack(file, widget.save.path);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
