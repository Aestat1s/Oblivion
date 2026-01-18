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

class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  
  
  static const int _totalPages = 6;

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishBootstrap();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
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
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Row(
        children: [
          
          
          
          
          
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(), 
                    onPageChanged: (page) => setState(() => _currentPage = page),
                    children: [
                      const _IntroPage(),
                      const _AccountPage(),
                      const _PersonalizationPage(),
                      const _InstallVersionPage(),
                      const _AnalyticsPage(),
                      const _LinksPage(),
                    ],
                  ),
                ),
                _buildBottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
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
              child: const Text('上一步'),
            )
          else
            const SizedBox.shrink(),
          
          Row(
            children: [
              
              for (int i = 0; i < _totalPages; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _currentPage
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              const SizedBox(width: 24),
              FilledButton(
                onPressed: _canProceed() ? _nextPage : null,
                child: Text(_currentPage == _totalPages - 1 ? '开始旅程' : '下一步'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _canProceed() {
    if (_currentPage == 1) { 
      final accountService = context.read<AccountService>();
      return accountService.accounts.isNotEmpty;
    }
    return true;
  }
}


class _IntroPage extends StatelessWidget {
  const _IntroPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(48.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.rocket_launch, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 32),
          Text(
            '欢迎使用 Oblivion Launcher',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            '一个现代化的、类 Material Design 3 风格的 Minecraft 启动器。',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          Text(
            '在这里，你可以轻松管理游戏版本、模组、账号，并享受美观流畅的交互体验。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}


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
            '请至少添加一个账号以继续。支持离线、微软和外置登录（Authlib）。',
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

          
          SwitchListTile(
            title: const Text('自定义背景'),
            value: settings.backgroundType != BackgroundType.none,
            onChanged: (value) {
              final newType = value ? BackgroundType.image : BackgroundType.none;
              final newSettings = settings.copyWith(backgroundType: newType);
              configService.updateSettings(newSettings);
              themeService.extractColorFromCurrentBackground(newSettings);
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
            subtitle: const Text('默认开启，感谢您的支持 ❤️'),
            value: settings.enableAnalytics,
            onChanged: (value) {
              if (!value) {
                
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('真的要关闭吗？🥺'),
                    content: const Text('这些数据对我们优化启动器非常重要。\n我们承诺数据完全匿名且开源透明。\n\n拜托拜托，就在开着嘛~'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          
                          configService.updateSettings(settings.copyWith(enableAnalytics: false));
                          Navigator.of(context).pop();
                        },
                        child: const Text('残忍拒绝'),
                      ),
                      FilledButton(
                        onPressed: () {
                          
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
                  title: const Text('GitHub 开源仓库'),
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
