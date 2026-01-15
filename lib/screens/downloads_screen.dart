import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/download_task.dart';
import '../services/download_service.dart';
import '../services/config_service.dart';
import '../models/config.dart';
import '../l10n/app_localizations.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final downloadService = context.watch<DownloadService>();
    final configService = context.watch<ConfigService>();
    final settings = configService.settings;
    final groups = downloadService.groups;
    final colorScheme = Theme.of(context).colorScheme;

    // 根据背景设置决定背景颜色
    final hasCustomBackground = settings.backgroundType != BackgroundType.none;
    final backgroundColor = hasCustomBackground 
        ? colorScheme.surface.withOpacity(0.85)
        : colorScheme.surface;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: l10n.get('back'),
        ),
        title: Text(l10n.get('download_management')),
        actions: [
          if (groups.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () => downloadService.clearCompleted(),
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: Text(l10n.get('clear_completed')),
            ),
            if (downloadService.isDownloading)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: () => downloadService.cancelAll(),
                  icon: Icon(Icons.stop, size: 18, color: colorScheme.error),
                  label: Text(l10n.get('stop_all'), 
                    style: TextStyle(color: colorScheme.error)),
                ),
              ),
          ],
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 下载进度概览
            if (downloadService.isDownloading)
              _buildOverviewCard(downloadService, colorScheme, l10n),
            
            if (downloadService.isDownloading)
              const SizedBox(height: 16),
            
            // 下载列表
            Expanded(
              child: groups.isEmpty
                  ? _buildEmptyState(colorScheme, l10n)
                  : _buildTaskList(groups, downloadService, colorScheme, l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(DownloadService service, ColorScheme colorScheme, AppLocalizations l10n) {
    final progress = service.totalCount > 0 ? service.completedCount / service.totalCount : 0.0;
    
    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.downloading, color: colorScheme.onPrimary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.get('downloading'), 
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
                      const SizedBox(height: 4),
                      Text(
                        '${service.completedCount} / ${service.totalCount} ${l10n.get('files')}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.download_done_rounded,
              size: 48,
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.get('no_downloads'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.get('download_hint'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(List<DownloadGroup> groups, DownloadService service, ColorScheme colorScheme, AppLocalizations l10n) {
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) => _buildGroupCard(groups[index], service, colorScheme, l10n),
    );
  }

  Widget _buildGroupCard(DownloadGroup group, DownloadService service, ColorScheme colorScheme, AppLocalizations l10n) {
    final isActive = group.status == DownloadStatus.downloading;
    final isFailed = group.status == DownloadStatus.failed;
    final isCompleted = group.status == DownloadStatus.completed;
    
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: isActive 
          ? colorScheme.primaryContainer.withOpacity(0.15)
          : isFailed 
              ? colorScheme.errorContainer.withOpacity(0.15)
              : colorScheme.surfaceContainerLow,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: isActive || isFailed,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: _buildStatusAvatar(group.status, colorScheme),
          title: Text(
            group.name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: group.progress / 100,
                  minHeight: 4,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    isCompleted ? colorScheme.primary 
                        : isFailed ? colorScheme.error 
                        : colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              
              Row(
                children: [
                  _buildStatusChip(group.status, colorScheme, l10n),
                  const SizedBox(width: 12),
                  Text(
                    '${group.completedTasks}/${group.totalTasks} ${l10n.get('files')}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_formatBytes(group.downloadedBytes)} / ${_formatBytes(group.totalBytes)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (group.failedTasks > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${group.failedTasks} ${l10n.get('files_failed')}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => service.removeGroup(group.id),
            tooltip: l10n.get('delete'),
          ),
          children: [
            if (group.tasks.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 250),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: group.tasks.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: colorScheme.outlineVariant.withOpacity(0.3)),
                  itemBuilder: (context, index) => _buildTaskItem(group.tasks[index], colorScheme, l10n),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusAvatar(DownloadStatus status, ColorScheme colorScheme) {
    final (icon, bgColor, fgColor) = switch (status) {
      DownloadStatus.pending => (Icons.schedule, colorScheme.surfaceContainerHighest, colorScheme.onSurfaceVariant),
      DownloadStatus.downloading => (Icons.downloading, colorScheme.primaryContainer, colorScheme.primary),
      DownloadStatus.completed => (Icons.check_circle, colorScheme.primaryContainer, colorScheme.primary),
      DownloadStatus.failed => (Icons.error, colorScheme.errorContainer, colorScheme.error),
      DownloadStatus.cancelled => (Icons.cancel, colorScheme.surfaceContainerHighest, colorScheme.outline),
    };
    
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: status == DownloadStatus.downloading
          ? Padding(
              padding: const EdgeInsets.all(10),
              child: CircularProgressIndicator(strokeWidth: 2.5, color: fgColor),
            )
          : Icon(icon, color: fgColor),
    );
  }

  Widget _buildTaskItem(DownloadTask task, ColorScheme colorScheme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _buildTaskStatusIcon(task.status, colorScheme),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  style: Theme.of(context).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                if (task.status == DownloadStatus.downloading)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: task.progress / 100,
                        minHeight: 3,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (task.status == DownloadStatus.failed && task.errorMessage != null)
            Tooltip(
              message: task.errorMessage!,
              child: Icon(Icons.info_outline, size: 18, color: colorScheme.error),
            )
          else
            Text(
              _formatBytes(task.totalBytes),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTaskStatusIcon(DownloadStatus status, ColorScheme colorScheme) {
    final (icon, color) = switch (status) {
      DownloadStatus.pending => (Icons.schedule, colorScheme.outline),
      DownloadStatus.downloading => (Icons.downloading, colorScheme.primary),
      DownloadStatus.completed => (Icons.check_circle, colorScheme.primary),
      DownloadStatus.failed => (Icons.error, colorScheme.error),
      DownloadStatus.cancelled => (Icons.cancel, colorScheme.outline),
    };
    
    if (status == DownloadStatus.downloading) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    }
    return Icon(icon, size: 18, color: color);
  }

  Widget _buildStatusChip(DownloadStatus status, ColorScheme colorScheme, AppLocalizations l10n) {
    final (label, bgColor, fgColor) = switch (status) {
      DownloadStatus.pending => (l10n.get('pending'), colorScheme.surfaceContainerHighest, colorScheme.onSurfaceVariant),
      DownloadStatus.downloading => (l10n.get('downloading'), colorScheme.primaryContainer, colorScheme.primary),
      DownloadStatus.completed => (l10n.get('completed'), colorScheme.primaryContainer, colorScheme.primary),
      DownloadStatus.failed => (l10n.get('failed'), colorScheme.errorContainer, colorScheme.error),
      DownloadStatus.cancelled => (l10n.get('cancelled'), colorScheme.surfaceContainerHighest, colorScheme.outline),
    };
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fgColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
