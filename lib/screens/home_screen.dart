import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../services/account_service.dart';
import '../services/game_service.dart';
import '../services/java_service.dart';
import '../services/config_service.dart';
import '../models/java_info.dart';
import '../l10n/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLaunching = false;
  String _launchStatus = '';
  String _gameLog = '';
  String _hitokoto = '';
  bool _gameCrashed = false;
  final ScrollController _logController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchHitokoto();
  }

  Future<void> _fetchHitokoto() async {
    try {
      final response = await http.get(Uri.parse('https://api.qaq.qa/api/hitokoto'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() => _hitokoto = data['hitokoto'] ?? '');
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<AccountService>();
    final gameService = context.watch<GameService>();
    final javaService = context.watch<JavaService>();
    context.watch<ConfigService>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        if (isWide) {
          return _buildWideLayout(accountService, gameService, javaService);
        } else {
          return _buildNarrowLayout(accountService, gameService, javaService);
        }
      },
    );
  }

  Widget _buildWideLayout(AccountService accountService, GameService gameService, JavaService javaService) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 320,
            child: Column(
              children: [
                _buildWelcomeCard(),
                const SizedBox(height: 12),
                _buildAccountCard(accountService),
                const SizedBox(height: 12),
                _buildVersionCard(gameService),
                const SizedBox(height: 12),
                _buildJavaCard(javaService),
                const Spacer(),
                _buildLaunchSection(),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(child: _buildLogCard()),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout(AccountService accountService, GameService gameService, JavaService javaService) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildWelcomeCard(),
          const SizedBox(height: 12),
          _buildAccountCard(accountService),
          const SizedBox(height: 12),
          _buildVersionCard(gameService),
          const SizedBox(height: 12),
          Expanded(child: _buildLogCard()),
          const SizedBox(height: 12),
          _buildLaunchSection(),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard() {
    final l10n = AppLocalizations.of(context);
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.onPrimary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.get('welcome_back'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    _hitokoto.isNotEmpty ? _hitokoto : l10n.get('ready_to_play'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.8),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard(AccountService service) {
    final l10n = AppLocalizations.of(context);
    final account = service.selectedAccount;
    return _InfoCard(
      icon: Icons.person,
      iconColor: Theme.of(context).colorScheme.primary,
      title: l10n.get('nav_accounts'),
      subtitle: account?.username ?? l10n.get('no_account_selected'),
      badge: account != null ? _getAccountTypeName(account.type) : null,
    );
  }

  String _getAccountTypeName(type) => switch (type.toString()) {
    'AccountType.offline' => '离线',
    'AccountType.microsoft' => '微软',
    'AccountType.authlibInjector' => '外置',
    _ => '',
  };

  Widget _buildVersionCard(GameService service) {
    final l10n = AppLocalizations.of(context);
    final profile = service.selectedVersion != null 
        ? service.getVersionProfile(service.selectedVersion!) 
        : null;
    final version = service.getInstalledVersion(service.selectedVersion ?? '');
    
    return _InfoCard(
      icon: Icons.games,
      iconColor: Theme.of(context).colorScheme.secondary,
      title: l10n.get('nav_versions'),
      subtitle: profile?.displayName ?? service.selectedVersion ?? l10n.get('no_version_selected'),
      badge: version?.type,
      onTap: () => _showVersionSelector(service),
    );
  }

  void _showVersionSelector(GameService service) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.get('select_version')),
        content: SizedBox(
          width: 400,
          height: 400,
          child: service.installedVersions.isEmpty
              ? Center(child: Text(l10n.get('no_version_selected')))
              : ListView.builder(
                  itemCount: service.installedVersions.length,
                  itemBuilder: (context, index) {
                    final v = service.installedVersions[index];
                    final p = service.getVersionProfile(v.id);
                    final isSelected = v.id == service.selectedVersion;
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.games, color: isSelected ? Theme.of(context).colorScheme.onPrimary : null, size: 20),
                      ),
                      title: Text(p?.displayName ?? v.id),
                      subtitle: Text(v.type),
                      trailing: isSelected ? const Icon(Icons.check) : null,
                      onTap: () {
                        service.selectVersion(v.id);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.get('cancel')))],
      ),
    );
  }

  Widget _buildJavaCard(JavaService service) {
    final l10n = AppLocalizations.of(context);
    final configService = context.read<ConfigService>();
    final gameService = context.read<GameService>();
    
    JavaInfo? java;
    String javaStatus = '';
    
    if (configService.settings.autoSelectJava) {
      final selectedVersion = gameService.selectedVersion;
      if (selectedVersion != null) {
        final version = gameService.getInstalledVersion(selectedVersion);
        final baseVersion = version?.inheritsFrom ?? selectedVersion;
        final (minJava, maxJava) = JavaService.getRequiredJavaVersion(baseVersion);
        java = service.selectJavaForVersion(minJava, maxVersion: maxJava);
        javaStatus = '自动 (${minJava}${maxJava != null ? "-$maxJava" : "+"})';
      } else {
        java = service.detectedJavas.isNotEmpty ? service.detectedJavas.first : null;
        javaStatus = '自动';
      }
    } else {
      final javaPath = configService.settings.javaPath;
      if (javaPath != null && javaPath.isNotEmpty) {
        java = service.getJavaByPath(javaPath);
      }
      java ??= service.detectedJavas.isNotEmpty ? service.detectedJavas.first : null;
      javaStatus = '手动';
    }
    
    return _InfoCard(
      icon: Icons.coffee,
      iconColor: Theme.of(context).colorScheme.tertiary,
      title: 'Java',
      subtitle: java != null ? 'Java ${java.majorVersion} (${java.vendor})' : l10n.get('no_version_selected'),
      badge: javaStatus,
      onTap: () => _showJavaDialog(service, configService),
    );
  }

  void _showJavaDialog(JavaService javaService, ConfigService configService) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final autoSelect = configService.settings.autoSelectJava;
          final javas = javaService.detectedJavas;
          
          return AlertDialog(
            title: Text(l10n.get('java_settings')),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: Text(l10n.get('auto_select_java')),
                    value: autoSelect,
                    onChanged: (v) {
                      configService.settings.autoSelectJava = v;
                      configService.save();
                      setDialogState(() {});
                      setState(() {});
                    },
                  ),
                  const Divider(),
                  if (javas.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l10n.get('no_version_selected')),
                    )
                  else
                    SizedBox(
                      height: 300,
                      child: ListView.builder(
                        itemCount: javas.length,
                        itemBuilder: (context, index) {
                          final java = javas[index];
                          final isSelected = configService.settings.javaPath == java.path;
                          final isCustom = javaService.customJavaPaths.contains(java.path);
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: Text('${java.majorVersion}', style: TextStyle(
                                color: isSelected ? Theme.of(context).colorScheme.onPrimary : null,
                                fontSize: 12,
                              )),
                            ),
                            title: Row(
                              children: [
                                Text('Java ${java.majorVersion}'),
                                if (isCustom) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.tertiaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('自定义', style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                                    )),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text('${java.vendor} - ${java.path}', maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: isSelected && !autoSelect ? const Icon(Icons.check) : null,
                            enabled: !autoSelect,
                            onTap: autoSelect ? null : () {
                              configService.settings.javaPath = java.path;
                              configService.save();
                              setDialogState(() {});
                              setState(() {});
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['exe'],
                    dialogTitle: l10n.get('select'),
                  );
                  if (result != null && result.files.single.path != null) {
                    final path = result.files.single.path!;
                    final success = await javaService.addCustomJava(path);
                    if (success) {
                      setDialogState(() {});
                      setState(() {});
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.get('error'))),
                        );
                      }
                    }
                  }
                },
                icon: const Icon(Icons.add),
                label: Text(l10n.get('add')),
              ),
              TextButton(
                onPressed: () {
                  javaService.scanJava();
                  setDialogState(() {});
                },
                child: Text(l10n.get('refresh')),
              ),
              FilledButton(onPressed: () => Navigator.pop(context), child: Text(l10n.get('close'))),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLogCard() {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.terminal, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(l10n.get('game_output'), style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: _exportLog,
                      icon: const Icon(Icons.save_alt, size: 18),
                      tooltip: l10n.get('export_log'),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      onPressed: _confirmClearLog,
                      icon: const Icon(Icons.clear_all, size: 18),
                      tooltip: l10n.get('clear_log'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
          Expanded(
            child: SingleChildScrollView(
              controller: _logController,
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _gameLog.isEmpty ? l10n.get('no_downloads') : _gameLog,
                style: TextStyle(
                  fontFamily: 'Consolas, monospace',
                  fontSize: 11,
                  height: 1.4,
                  color: _gameLog.isEmpty 
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClearLog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.get('clear_log')),
        content: Text(l10n.get('clear_log_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.get('cancel'))),
          FilledButton(
            onPressed: () {
              setState(() => _gameLog = '');
              Navigator.pop(context);
            },
            child: Text(l10n.get('confirm')),
          ),
        ],
      ),
    );
  }

  Future<void> _exportLog() async {
    if (_gameLog.isEmpty) return;
    
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Log',
      fileName: 'game_log_${DateTime.now().toIso8601String().replaceAll(':', '-')}.txt',
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    
    if (result != null) {
      await File(result).writeAsString(_gameLog);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Log exported to $result')));
      }
    }
  }

  Widget _buildLaunchSection() {
    final l10n = AppLocalizations.of(context);
    final gameService = context.watch<GameService>();
    final isRunning = gameService.isGameRunning;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isLaunching) ...[
          LinearProgressIndicator(borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 8),
        ],
        Text(
          _launchStatus.isEmpty 
              ? (isRunning ? l10n.get('game_running') : l10n.get('ready_to_play')) 
              : _launchStatus,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _isLaunching ? null : (isRunning ? _stopGame : () => _launchGame(context)),
          icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
          label: Text(isRunning ? l10n.get('stop_game') : l10n.get('launch_game')),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            backgroundColor: isRunning ? Theme.of(context).colorScheme.error : null,
            foregroundColor: isRunning ? Theme.of(context).colorScheme.onError : null,
          ),
        ),
      ],
    );
  }

  void _stopGame() {
    final gameService = context.read<GameService>();
    gameService.stopGame();
    setState(() {
      _launchStatus = '';
      _isLaunching = false;
    });
  }

  Future<void> _launchGame(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final accountService = context.read<AccountService>();
    final gameService = context.read<GameService>();
    final javaService = context.read<JavaService>();

    if (accountService.selectedAccount == null) {
      setState(() => _launchStatus = l10n.get('no_account_selected'));
      return;
    }
    if (gameService.selectedVersion == null) {
      setState(() => _launchStatus = l10n.get('no_version_selected'));
      return;
    }

    setState(() {
      _isLaunching = true;
      _launchStatus = l10n.get('loading');
      _gameLog = '';
      _gameCrashed = false;
    });

    try {
      await gameService.launchGame(
        accountService.selectedAccount!,
        javaService: javaService,
        onOutput: (line) {
          setState(() => _gameLog += line);
          _checkForCrash(line);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_logController.hasClients) {
              _logController.jumpTo(_logController.position.maxScrollExtent);
            }
          });
        },
        onStatusChange: (status) => setState(() => _launchStatus = status),
      );
      setState(() => _launchStatus = l10n.get('success'));
    } catch (e) {
      setState(() {
        _launchStatus = '${l10n.get('error_launch_failed')}: $e';
        _gameCrashed = true;
      });
      _showCrashDialog();
    } finally {
      setState(() => _isLaunching = false);
    }
  }

  void _checkForCrash(String line) {
    final crashIndicators = [
      'EXCEPTION_ACCESS_VIOLATION',
      'java.lang.OutOfMemoryError',
      'Minecraft has crashed',
      'The game crashed',
      'Fatal error',
      'A fatal error has been detected',
    ];
    
    for (final indicator in crashIndicators) {
      if (line.contains(indicator) && !_gameCrashed) {
        _gameCrashed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _showCrashDialog());
        break;
      }
    }
  }

  void _showCrashDialog() {
    final l10n = AppLocalizations.of(context);
    
    
    final logLines = _gameLog.split('\n').where((line) => line.trim().isNotEmpty).toList();
    
    
    final errorLines = logLines.where((line) =>
      line.contains('Error') || line.contains('Exception') || 
      line.contains('FATAL') || line.contains('Caused by') ||
      line.contains('at ') || line.contains('failed') ||
      line.contains('Unable to') || line.contains('Cannot')
    ).take(50).toList();
    
    
    final displayLog = errorLines.isNotEmpty 
        ? errorLines.join('\n') 
        : logLines.skip(logLines.length > 50 ? logLines.length - 50 : 0).join('\n');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Text(l10n.get('game_crashed')),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.get('crash_log_title'), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      displayLog.isEmpty ? '无日志信息' : displayLog,
                      style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.get('close'))),
          FilledButton.icon(
            onPressed: () => _exportCrashLog(),
            icon: const Icon(Icons.save_alt),
            label: Text(l10n.get('export_crash_log')),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCrashLog() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Crash Log',
      fileName: 'crash_${DateTime.now().toIso8601String().replaceAll(':', '-')}.txt',
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    
    if (result != null) {
      final deviceInfo = '''
=== Device Info ===
OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}
Dart: ${Platform.version}
Time: ${DateTime.now().toIso8601String()}

=== Game Log ===
$_gameLog
''';
      await File(result).writeAsString(deviceInfo);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Crash log exported')));
      }
    }
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback? onTap;

  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: Theme.of(context).textTheme.labelMedium),
                        if (badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(badge!, style: Theme.of(context).textTheme.labelSmall),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
