import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/config_service.dart';
import '../services/java_service.dart';
import '../models/config.dart';
import '../l10n/app_localizations.dart';
import '../widgets/personalization_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JavaService>().scanJava();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = context.watch<ConfigService>();
    final javaService = context.watch<JavaService>();
    final settings = config.settings;
    final screenWidth = MediaQuery.of(context).size.width;
    // Use two-column layout only when width is sufficient (> 900px)
    final isWide = screenWidth > 900;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.get('settings'), style: Theme.of(context).textTheme.headlineMedium),
          Text(l10n.get('settings_hint'), style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )),
          const SizedBox(height: 24),
          isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildLeftColumn(config, javaService, settings, l10n)),
                    const SizedBox(width: 24),
                    Expanded(child: _buildRightColumn(config, settings, l10n)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildLeftColumn(config, javaService, settings, l10n),
                    _buildRightColumn(config, settings, l10n),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildLeftColumn(ConfigService config, JavaService javaService, GlobalSettings settings, AppLocalizations l10n) {
    return Column(
      children: [
        _buildSection(l10n.get('game_settings'), Icons.games, [
          ListTile(
            title: Text(l10n.get('game_directory')),
            subtitle: Text(config.gameDirectory, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: FilledButton.tonal(
              onPressed: () async {
                final result = await FilePicker.platform.getDirectoryPath();
                if (result != null) {
                  config.setGameDirectory(result);
                  setState(() {});
                }
              },
              child: Text(l10n.get('select')),
            ),
          ),
          ListTile(
            title: Text(l10n.get('version_isolation')),
            subtitle: Text(_getIsolationDesc(settings.defaultIsolation, l10n)),
            trailing: SegmentedButton<IsolationType>(
              segments: [
                ButtonSegment(value: IsolationType.none, label: Text(l10n.get('isolation_none'))),
                ButtonSegment(value: IsolationType.partial, label: Text(l10n.get('isolation_partial'))),
                ButtonSegment(value: IsolationType.full, label: Text(l10n.get('isolation_full'))),
              ],
              selected: {settings.defaultIsolation},
              onSelectionChanged: (s) {
                settings.defaultIsolation = s.first;
                config.save();
                setState(() {});
              },
            ),
          ),
          SwitchListTile(
            title: Text(l10n.get('auto_complete_files')),
            subtitle: Text(l10n.get('auto_complete_files_hint')),
            value: settings.autoCompleteFiles,
            onChanged: (v) {
              settings.autoCompleteFiles = v;
              config.save();
              setState(() {});
            },
          ),
        ]),
        _buildSection('Java', Icons.coffee, [
          SwitchListTile(
            title: Text(l10n.get('auto_select_java')),
            subtitle: Text(l10n.get('auto_select_java_hint')),
            value: settings.autoSelectJava,
            onChanged: (v) {
              settings.autoSelectJava = v;
              if (v) settings.javaPath = null;
              config.save();
              setState(() {});
            },
          ),
          ListTile(
            title: Text(l10n.get('java_path')),
            subtitle: Text(settings.javaPath ?? l10n.get('use_auto_select'), maxLines: 1, overflow: TextOverflow.ellipsis),
            enabled: !settings.autoSelectJava,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (javaService.detectedJavas.isNotEmpty)
                  PopupMenuButton<String>(
                    enabled: !settings.autoSelectJava,
                    icon: const Icon(Icons.arrow_drop_down),
                    onSelected: (path) {
                      settings.javaPath = path;
                      config.save();
                      setState(() {});
                    },
                    itemBuilder: (context) => javaService.detectedJavas.map((j) => PopupMenuItem(
                      value: j.path,
                      child: Text(j.displayName),
                    )).toList(),
                  ),
                IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: settings.autoSelectJava ? null : () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['exe'],
                    );
                    if (result != null && result.files.single.path != null) {
                      settings.javaPath = result.files.single.path;
                      config.save();
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
          ),
          ListTile(
            title: Text(l10n.get('scan_java')),
            subtitle: Text('${l10n.get('found')} ${javaService.detectedJavas.length} ${l10n.get('java_count')}'),
            trailing: javaService.isScanning
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(icon: const Icon(Icons.refresh), onPressed: () => javaService.scanJava()),
          ),
        ]),
      ],
    );
  }

  Widget _buildRightColumn(ConfigService config, GlobalSettings settings, AppLocalizations l10n) {
    return Column(
      children: [
        const PersonalizationSettings(),
        _buildSection(l10n.get('memory_settings'), Icons.memory, [
          SwitchListTile(
            title: Text(l10n.get('dynamic_memory')),
            subtitle: Text(l10n.get('dynamic_memory_hint')),
            value: settings.dynamicMemory,
            onChanged: (v) {
              settings.dynamicMemory = v;
              config.save();
              setState(() {});
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.get('max_memory')),
                    Text('${settings.maxMemory} MB', style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
                Slider(
                  value: settings.maxMemory.toDouble(),
                  min: 512,
                  max: 16384,
                  divisions: 31,
                  onChanged: (v) {
                    settings.maxMemory = v.toInt();
                    if (settings.minMemory > settings.maxMemory) {
                      settings.minMemory = settings.maxMemory;
                    }
                    config.save();
                    setState(() {});
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.get('min_memory')),
                    Text('${settings.minMemory} MB', style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
                Slider(
                  value: settings.minMemory.toDouble(),
                  min: 256,
                  max: settings.maxMemory.toDouble(),
                  divisions: 31,
                  onChanged: (v) {
                    settings.minMemory = v.toInt();
                    config.save();
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ]),
        _buildSection(l10n.get('download_settings'), Icons.download, [
          ListTile(
            title: Text(l10n.get('download_source')),
            trailing: SegmentedButton<DownloadSource>(
              segments: [
                ButtonSegment(value: DownloadSource.official, label: Text(l10n.get('source_official'))),
                ButtonSegment(value: DownloadSource.bmclapi, label: const Text('BMCLAPI')),
              ],
              selected: {settings.downloadSource},
              onSelectionChanged: (s) {
                settings.downloadSource = s.first;
                config.save();
                setState(() {});
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.get('concurrent_downloads')),
                    Text('${settings.concurrentDownloads}', style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
                Slider(
                  value: settings.concurrentDownloads.toDouble(),
                  min: 1,
                  max: 128,
                  divisions: 127,
                  onChanged: (v) {
                    settings.concurrentDownloads = v.toInt();
                    config.save();
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ]),
        _buildSection(l10n.get('window_size'), Icons.aspect_ratio, [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(labelText: l10n.get('width'), isDense: true),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: '${settings.windowWidth}'),
                    onSubmitted: (v) {
                      final width = int.tryParse(v);
                      if (width != null && width > 0) {
                        settings.windowWidth = width;
                        config.save();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(labelText: l10n.get('height'), isDense: true),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: '${settings.windowHeight}'),
                    onSubmitted: (v) {
                      final height = int.tryParse(v);
                      if (height != null && height > 0) {
                        settings.windowHeight = height;
                        config.save();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: Text(l10n.get('fullscreen')),
            value: settings.fullscreen,
            onChanged: (v) {
              settings.fullscreen = v;
              config.save();
              setState(() {});
            },
          ),
        ]),
      ],
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer, size: 18),
                ),
                const SizedBox(width: 12),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
          ...children,
        ],
      ),
    );
  }

  String _getIsolationDesc(IsolationType type, AppLocalizations l10n) => switch (type) {
    IsolationType.none => l10n.get('isolation_none_desc'),
    IsolationType.partial => l10n.get('isolation_partial_desc'),
    IsolationType.full => l10n.get('isolation_full_desc'),
  };
}
