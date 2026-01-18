import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../models/game_version.dart';
import '../models/config.dart';
import 'version_resources_screen.dart';

class VersionsScreen extends StatefulWidget {
  const VersionsScreen({super.key});

  @override
  State<VersionsScreen> createState() => _VersionsScreenState();
}

class _VersionsScreenState extends State<VersionsScreen> {
  String? _selectedVersionForDetails;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GameService>().refreshVersions();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gameService = context.watch<GameService>();
    final isWide = MediaQuery.of(context).size.width > 900;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: isWide 
          ? _buildWideLayout(gameService)
          : _buildNarrowLayout(gameService),
    );
  }

  Widget _buildWideLayout(GameService gameService) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _buildVersionList(gameService)),
        const SizedBox(width: 24),
        Expanded(
          flex: 1,
          child: _selectedVersionForDetails != null
              ? _buildVersionDetails(gameService, _selectedVersionForDetails!)
              : _buildNoSelectionHint(),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(GameService gameService) {
    return _buildVersionList(gameService);
  }

  Widget _buildVersionList(GameService gameService) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('版本管理', style: Theme.of(context).textTheme.headlineMedium),
            Row(
              children: [
                IconButton(
                  onPressed: () => gameService.refreshVersions(),
                  icon: gameService.isLoading
                      ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary))
                      : const Icon(Icons.refresh),
                  tooltip: '刷新',
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(child: _buildInstalledVersionList(gameService)),
      ],
    );
  }

  Widget _buildInstalledVersionList(GameService gameService) {
    final versions = gameService.installedVersions;
    if (versions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.folder_off, size: 40, color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 16),
            Text('暂无已安装版本', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('前往下载中心安装游戏', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: versions.length,
      itemBuilder: (context, index) {
        final version = versions[index];
        final profile = gameService.getVersionProfile(version.id);
        final isSelected = version.id == gameService.selectedVersion;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
          child: InkWell(
            onTap: () {
              gameService.selectVersion(version.id);
              setState(() => _selectedVersionForDetails = version.id);
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.games,
                      color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.displayName ?? version.id,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: isSelected ? FontWeight.bold : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _buildBadge(version.type),
                            if (version.javaVersion != null) ...[
                              const SizedBox(width: 8),
                              _buildBadge('Java ${version.javaVersion}'),
                            ],
                            if (profile?.isolation != IsolationType.none) ...[
                              const SizedBox(width: 8),
                              _buildBadge('隔离'),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (action) => _handleVersionAction(action, version.id),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings), title: Text('版本设置'), dense: true)),
                      const PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit), title: Text('重命名'), dense: true)),
                      const PopupMenuItem(value: 'duplicate', child: ListTile(leading: Icon(Icons.copy), title: Text('复制'), dense: true)),
                      const PopupMenuItem(value: 'backup', child: ListTile(leading: Icon(Icons.archive), title: Text('备份'), dense: true)),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('删除', style: TextStyle(color: Colors.red)), dense: true)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }

  void _handleVersionAction(String action, String versionId) async {
    switch (action) {
      case 'settings':
        _showVersionSettings(versionId);
      case 'rename':
        _showRenameDialog(versionId);
      case 'duplicate':
        _showDuplicateDialog(versionId);
      case 'backup':
        _backupVersion(versionId);
      case 'delete':
        _showDeleteDialog(versionId);
    }
  }

  Widget _buildVersionDetails(GameService gameService, String versionId) {
    final version = gameService.getInstalledVersion(versionId);
    final profile = gameService.getVersionProfile(versionId);
    
    if (version == null) return _buildNoSelectionHint();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.games, size: 28, color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile?.displayName ?? version.id, style: Theme.of(context).textTheme.titleLarge),
                      Text(version.type, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildDetailRow('版本 ID', version.id),
            _buildDetailRow('类型', version.type),
            if (version.inheritsFrom != null) _buildDetailRow('继承自', version.inheritsFrom!),
            if (version.javaVersion != null) _buildDetailRow('Java 版本', 'Java ${version.javaVersion}'),
            _buildDetailRow('版本隔离', _getIsolationName(profile?.isolation ?? IsolationType.none)),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showVersionSettings(version.id),
                    icon: const Icon(Icons.settings),
                    label: const Text('设置'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VersionResourcesScreen(version: version),
                      ),
                    ),
                    icon: const Icon(Icons.folder_special),
                    label: const Text('资源管理'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  


  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  String _getIsolationName(IsolationType type) => switch (type) {
    IsolationType.none => '不隔离',
    IsolationType.partial => '部分隔离',
    IsolationType.full => '完全隔离',
  };

  Widget _buildNoSelectionHint() {
    return Card(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('选择一个版本查看详情', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  void _showVersionSettings(String versionId) {
    showDialog(context: context, builder: (context) => _VersionSettingsDialog(versionId: versionId));
  }

  void _showRenameDialog(String versionId) {
    final controller = TextEditingController(text: versionId);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名版本'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: '新名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              if (controller.text.isNotEmpty && controller.text != versionId) {
                try {
                  await context.read<GameService>().renameVersion(versionId, controller.text);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重命名失败: $e')));
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDuplicateDialog(String versionId) {
    final controller = TextEditingController(text: '$versionId-copy');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('复制版本'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: '新版本名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                try {
                  await context.read<GameService>().duplicateVersion(versionId, controller.text);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('复制完成')));
                  }
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('复制失败: $e')));
                }
              }
            },
            child: const Text('复制'),
          ),
        ],
      ),
    );
  }

  void _backupVersion(String versionId) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在备份...')));
    try {
      final path = await context.read<GameService>().backupVersion(versionId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('备份完成: $path')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('备份失败: $e')));
    }
  }

  void _showDeleteDialog(String versionId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除版本'),
        content: Text('确定要删除 "$versionId" 吗？\n文件将移动到回收站。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              await context.read<GameService>().deleteVersion(versionId);
              if (context.mounted) {
                Navigator.pop(context);
                setState(() => _selectedVersionForDetails = null);
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _VersionSettingsDialog extends StatefulWidget {
  final String versionId;
  const _VersionSettingsDialog({required this.versionId});

  @override
  State<_VersionSettingsDialog> createState() => _VersionSettingsDialogState();
}

class _VersionSettingsDialogState extends State<_VersionSettingsDialog> {
  late VersionProfile _profile;
  bool _useCustomJava = false;
  bool _useCustomMemory = false;

  @override
  void initState() {
    super.initState();
    final gameService = context.read<GameService>();
    _profile = gameService.getVersionProfile(widget.versionId) ?? VersionProfile(versionId: widget.versionId);
    _useCustomJava = _profile.javaPath != null;
    _useCustomMemory = _profile.maxMemory != null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${_profile.displayName} 设置'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: '显示名称'),
                controller: TextEditingController(text: _profile.displayName),
                onChanged: (v) => _profile.displayName = v,
              ),
              const SizedBox(height: 16),
              Text('版本隔离', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<IsolationType>(
                segments: const [
                  ButtonSegment(value: IsolationType.none, label: Text('不隔离')),
                  ButtonSegment(value: IsolationType.partial, label: Text('部分')),
                  ButtonSegment(value: IsolationType.full, label: Text('完全')),
                ],
                selected: {_profile.isolation},
                onSelectionChanged: (s) => setState(() => _profile.isolation = s.first),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('自定义 Java'),
                value: _useCustomJava,
                onChanged: (v) => setState(() {
                  _useCustomJava = v;
                  if (!v) _profile.javaPath = null;
                }),
              ),
              if (_useCustomJava)
                TextField(
                  decoration: const InputDecoration(labelText: 'Java 路径'),
                  controller: TextEditingController(text: _profile.javaPath),
                  onChanged: (v) => _profile.javaPath = v,
                ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('自定义内存'),
                value: _useCustomMemory,
                onChanged: (v) => setState(() {
                  _useCustomMemory = v;
                  if (!v) {
                    _profile.minMemory = null;
                    _profile.maxMemory = null;
                  }
                }),
              ),
              if (_useCustomMemory) ...[
                Text('最大内存: ${_profile.maxMemory ?? 4096} MB'),
                Slider(
                  value: (_profile.maxMemory ?? 4096).toDouble(),
                  min: 512,
                  max: 16384,
                  divisions: 31,
                  onChanged: (v) => setState(() => _profile.maxMemory = v.toInt()),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () async {
            await context.read<GameService>().saveVersionProfile(_profile);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}



