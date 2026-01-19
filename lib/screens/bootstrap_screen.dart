import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../services/config_service.dart';
import '../services/account_service.dart';
import '../services/game_service.dart';
import '../services/theme_service.dart';
import '../models/config.dart';
import '../models/game_version.dart';
import '../widgets/add_account_dialog.dart';
import 'main_screen.dart';
import '../l10n/app_localizations.dart';

class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  
  // Total pages: Intro, Account, Personalization, Install Version, Analytics, Links
  static const int _totalPages = 6;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubicEmphasized,
      );
    } else {
      _finishBootstrap();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubicEmphasized,
      );
    }
  }

  Future<void> _finishBootstrap() async {
    final configService = context.read<ConfigService>();
    configService.settings.isFirstRun = false;
    await configService.save();

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                itemCount: _totalPages,
                itemBuilder: (context, index) {
                  return _getPage(index);
                },
              ),
                ),
                _buildBottomBar(l10n),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _getPage(int index) {
    switch (index) {
      case 0: return const _IntroPage();
      case 1: return const _AccountPage();
      case 2: return const _PersonalizationPage();
      case 3: return const _InstallVersionPage();
      case 4: return const _AnalyticsPage();
      case 5: return const _LinksPage();
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentPage > 0)
            TextButton(
              onPressed: _prevPage,
              child: Text(l10n.get('previous')),
            )
          else
            const SizedBox.shrink(),
          
          Row(
            children: [
              // Page indicator
              for (int i = 0; i < _totalPages; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: i == _currentPage ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: i == _currentPage
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              const SizedBox(width: 24),
              FilledButton(
                onPressed: _canProceed() ? _nextPage : null,
                child: Text(_currentPage == _totalPages - 1 ? l10n.get('finish') : l10n.get('next')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _canProceed() {
    if (_currentPage == 1) { // Account Page
      final accountService = context.read<AccountService>();
      return accountService.accounts.isNotEmpty;
    }
    return true;
  }
}

// 1. Intro Page
class _IntroPage extends StatelessWidget {
  const _IntroPage();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final configService = context.watch<ConfigService>();
    
    return Padding(
      padding: const EdgeInsets.all(48.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.rocket_launch, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 32),
          Text(
            l10n.get('welcome'),
            style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.get('welcome_desc'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.language, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text(l10n.get('choose_language')),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: ['en', 'zh'].contains(configService.settings.language) ? configService.settings.language : 'zh',
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'zh', child: Text('简体中文')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      configService.updateSettings(configService.settings.copyWith(language: value));
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 2. Account Page
class _AccountPage extends StatelessWidget {
  const _AccountPage();

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<AccountService>();
    final accounts = accountService.accounts;

    return Padding(
      padding: const EdgeInsets.all(48.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '添加账号',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(
            '请至少添加一个账号以继续。支持离线、微软和外置登录（俗称皮肤站）。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 32),
          if (accounts.isEmpty)
            Center(
              child: Column(
                children: [
                  Icon(Icons.person_add, size: 48, color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(height: 16),
                  Text('暂无账号', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: accounts.length,
                itemBuilder: (context, index) {
                  final account = accounts[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(child: Text(account.username[0].toUpperCase())),
                      title: Text(account.username),
                      subtitle: Text(account.type.name),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => accountService.removeAccount(account.id),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const AddAccountDialog(),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('添加账号'),
            ),
          ),
        ],
      ),
    );
  }
}

// 3. Personalization Page
class _PersonalizationPage extends StatelessWidget {
  const _PersonalizationPage();

  @override
  Widget build(BuildContext context) {
    final configService = context.watch<ConfigService>();
    final themeService = context.watch<ThemeService>();
    final settings = configService.settings;

    return Padding(
      padding: const EdgeInsets.all(48.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '个性化设置',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 32),
          
          // Theme Mode
          Text('主题模式', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('跟随系统'), icon: Icon(Icons.brightness_auto)),
              ButtonSegment(value: ThemeMode.light, label: Text('浅色'), icon: Icon(Icons.brightness_5)),
              ButtonSegment(value: ThemeMode.dark, label: Text('深色'), icon: Icon(Icons.brightness_2)),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (Set<ThemeMode> newSelection) {
              configService.updateSettings(settings.copyWith(themeMode: newSelection.first));
            },
          ),
          const SizedBox(height: 24),

          // Background
          Text('背景设置', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<BackgroundType>(
            segments: const [
              ButtonSegment(value: BackgroundType.none, label: Text('默认'), icon: Icon(Icons.block)),
              ButtonSegment(value: BackgroundType.image, label: Text('图片'), icon: Icon(Icons.image)),
              ButtonSegment(value: BackgroundType.randomImage, label: Text('随机'), icon: Icon(Icons.shuffle)),
            ],
            selected: {settings.backgroundType},
            onSelectionChanged: (Set<BackgroundType> newSelection) {
              final newType = newSelection.first;
              var newSettings = settings.copyWith(backgroundType: newType);
              if (newType == BackgroundType.randomImage && (newSettings.randomImageApi == null || newSettings.randomImageApi!.isEmpty)) {
                 newSettings = newSettings.copyWith(randomImageApi: 'https://bing.img.run/rand.php');
              }
              configService.updateSettings(newSettings);
              themeService.extractColorFromCurrentBackground(newSettings);
            },
          ),
          const SizedBox(height: 16),

          if (settings.backgroundType == BackgroundType.randomImage)
            TextField(
              decoration: const InputDecoration(
                labelText: '随机图片 API',
                hintText: 'https://bing.img.run/rand.php',
                prefixIcon: Icon(Icons.link),
              ),
              controller: TextEditingController(text: settings.randomImageApi)
                ..selection = TextSelection.collapsed(offset: settings.randomImageApi?.length ?? 0),
              onChanged: (value) {
                configService.updateSettings(settings.copyWith(randomImageApi: value));
              },
              onSubmitted: (value) {
                 themeService.extractColorFromCurrentBackground(settings.copyWith(randomImageApi: value));
              },
            ),

          if (settings.backgroundType == BackgroundType.image)
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      settings.customBackgroundPath ?? '未选择图片',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                      );
                      if (result != null) {
                        final path = result.files.single.path!;
                        final newSettings = settings.copyWith(customBackgroundPath: path);
                        configService.updateSettings(newSettings);
                        themeService.extractColorFromCurrentBackground(newSettings);
                      }
                    },
                    child: const Text('选择图片'),
                  ),
                ],
              ),
            ),
            
          const SizedBox(height: 24),

          // Theme Color Source
          Text('主题取色', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeColorSource>(
            segments: const [
              ButtonSegment(value: ThemeColorSource.system, label: Text('系统'), icon: Icon(Icons.desktop_windows)),
              ButtonSegment(value: ThemeColorSource.customBackground, label: Text('壁纸'), icon: Icon(Icons.image)),
              ButtonSegment(value: ThemeColorSource.manual, label: Text('固定'), icon: Icon(Icons.color_lens)),
            ],
            selected: {settings.themeColorSource},
            onSelectionChanged: (Set<ThemeColorSource> newSelection) {
              final newSettings = settings.copyWith(
                enableCustomColor: true,
                themeColorSource: newSelection.first,
              );
              configService.updateSettings(newSettings);
              themeService.updateThemeColor(newSettings);
            },
          ),
          const SizedBox(height: 24),

          // Announcement
          SwitchListTile(
            title: const Text('显示首页公告'),
            value: settings.showAnnouncement,
            onChanged: (value) {
              configService.updateSettings(settings.copyWith(showAnnouncement: value));
            },
          ),
        ],
      ),
    );
  }
}

// 4. Install Version Page
class _InstallVersionPage extends StatefulWidget {
  const _InstallVersionPage();

  @override
  State<_InstallVersionPage> createState() => _InstallVersionPageState();
}

class _InstallVersionPageState extends State<_InstallVersionPage> {
  bool _isLoading = false;
  String? _statusMessage;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GameService>().refreshVersions();
    });
  }

  Future<void> _installVersion(GameVersion version) async {
    setState(() {
      _isLoading = true;
      _statusMessage = '准备安装...';
      _progress = 0.0;
    });

    try {
      final gameService = context.read<GameService>();
      await gameService.installVersion(
        version,
        onStatus: (status) {
          if (mounted) setState(() => _statusMessage = status);
        },
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已安装 ${version.id}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('安装失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameService = context.watch<GameService>();
    final versions = gameService.availableVersions;
    
    // Find latest release and snapshot
    final release = versions.where((v) => v.type == 'release').firstOrNull;
    final snapshot = versions.where((v) => v.type == 'snapshot').firstOrNull;

    return Padding(
      padding: const EdgeInsets.all(48.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '安装游戏版本',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(
            '为您推荐最新的游戏版本。您可以现在安装，也可以稍后在“下载中心”安装。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 32),
          
          if (_isLoading) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(_statusMessage ?? '正在处理...'),
          ] else ...[
            if (release != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.grass),
                  title: Text('最新正式版 ${release.id}'),
                  subtitle: Text('发布时间: ${release.releaseTime}'),
                  trailing: FilledButton.tonal(
                    onPressed: () => _installVersion(release),
                    child: const Text('安装'),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (snapshot != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.bug_report),
                  title: Text('最新快照版 ${snapshot.id}'),
                  subtitle: Text('发布时间: ${snapshot.releaseTime}'),
                  trailing: FilledButton.tonal(
                    onPressed: () => _installVersion(snapshot),
                    child: const Text('安装'),
                  ),
                ),
              ),
            if (release == null && snapshot == null)
              const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}

// 5. Analytics Page
class _AnalyticsPage extends StatelessWidget {
  const _AnalyticsPage();

  @override
  Widget build(BuildContext context) {
    final configService = context.watch<ConfigService>();
    final settings = configService.settings;

    return Padding(
      padding: const EdgeInsets.all(48.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '更新与改进',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(
            '配置自动更新和数据收集选项。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 32),
          SwitchListTile(
            title: const Text('自动更新'),
            subtitle: const Text('保持启动器为最新版本（推荐）'),
            value: settings.autoUpdate,
            onChanged: (value) {
              configService.updateSettings(settings.copyWith(autoUpdate: value));
            },
          ),
          SwitchListTile(
            title: const Text('允许发送匿名统计数据'),
            subtitle: const Text('帮助我们改进启动器'),
            value: settings.enableAnalytics,
            onChanged: (value) {
              if (!value) {
                // Show begging dialog
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('真的要关闭吗'),
                    content: const Text('这些数据对我们优化启动器非常重要。\n我们承诺数据完全匿名且开源透明。'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          // Cruel user confirms disable
                          configService.updateSettings(settings.copyWith(enableAnalytics: false));
                          Navigator.of(context).pop();
                        },
                        child: const Text('我拒绝'),
                      ),
                      FilledButton(
                        onPressed: () {
                          // User keeps it enabled
                          Navigator.of(context).pop();
                        },
                        child: const Text('保持开启'),
                      ),
                    ],
                  ),
                );
              } else {
                configService.updateSettings(settings.copyWith(enableAnalytics: true));
              }
            },
          ),
        ],
      ),
    );
  }
}

// 6. Links Page
class _LinksPage extends StatelessWidget {
  const _LinksPage();

  Future<void> _launchUrl(String url) async {
    if (!await launchUrl(Uri.parse(url))) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(48.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '准备就绪',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(
            '一切准备就绪！您可以访问以下链接了解更多信息，或直接开始使用。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 32),
          
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('GitHub 仓库'),
                  subtitle: const Text('github.com/Aestat1s/Oblivion'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchUrl('https://github.com/Aestat1s/Oblivion'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.web),
                  title: const Text('官方网站'),
                  subtitle: const Text('www.aestat1s.com'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchUrl('https://www.aestat1s.com'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
