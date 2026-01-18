import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'dart:io';
import 'app.dart';
import 'services/config_service.dart';
import 'services/account_service.dart';
import 'services/game_service.dart';
import 'services/java_service.dart';
import 'services/download_service.dart';
import 'services/mod_download_service.dart';
import 'services/resource_download_service.dart';
import 'services/favorites_service.dart';
import 'services/theme_service.dart';
import 'services/modpack_install_service.dart';
import 'services/mod_service.dart';
import 'services/debug_logger.dart';
import 'services/analytics_service.dart';
import 'services/update_service.dart';
import 'services/resource_service.dart';
import 'models/config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DebugLogger().init();
  debugLog('App starting...');

  await Window.initialize();
  debugLog('Window.initialize() completed');

  await windowManager.ensureInitialized();
  debugLog('windowManager.ensureInitialized() completed');

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1200, 800),
    minimumSize: Size(360, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final configService = ConfigService();
  await configService.load();
  debugLog('Config loaded');

  final downloadService = DownloadService();
  final modDownloadService = ModDownloadService(downloadService);
  final resourceDownloadService = ResourceDownloadService(downloadService);
  final favoritesService = FavoritesService(configService.gameDirectory);
  final javaService = JavaService();
  javaService.init();

  final themeService = ThemeService();
  await themeService.initialize(configService.settings);

  final analyticsService = AnalyticsService();
  await analyticsService.init();

  final updateService = UpdateService();
  

  if (configService.settings.backgroundType == BackgroundType.image ||
      configService.settings.backgroundType == BackgroundType.randomImage) {
    await themeService.extractColorFromCurrentBackground(configService.settings);
  }

  await applyWindowEffect(configService.settings);
  debugLog('Window effect applied');

  debugLog('Services initialized, starting app...');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => configService),
        ChangeNotifierProvider(create: (_) => downloadService),
        ChangeNotifierProvider(create: (_) => AccountService(configService)),
        ChangeNotifierProvider(create: (context) => GameService(configService, analyticsService)),
        ChangeNotifierProvider.value(value: javaService),
        ChangeNotifierProvider.value(value: modDownloadService),
        ChangeNotifierProvider.value(value: resourceDownloadService),
        ChangeNotifierProvider.value(value: favoritesService),
        ChangeNotifierProvider.value(value: themeService),
        Provider.value(value: analyticsService),
        ChangeNotifierProvider(create: (_) => updateService),
        ChangeNotifierProvider(create: (_) => ModService(configService.gameDirectory)),
        ChangeNotifierProvider(create: (_) => ResourceService()),
        ChangeNotifierProxyProvider2<GameService, DownloadService, ModpackInstallService>(
          create: (context) => ModpackInstallService(
            context.read<GameService>(),
            downloadService,
            configService,
          ),
          update: (context, gameService, downloadService, previous) =>
            previous ?? ModpackInstallService(gameService, downloadService, configService),
        ),
      ],
      child: const OblivionApp(),
    ),
  );
}

Future<void> applyWindowEffect(GlobalSettings settings) async {
  if (!Platform.isWindows) return;

  try {
    debugLog('Applying window effect: ${settings.backgroundType}');

    switch (settings.backgroundType) {
      case BackgroundType.image:
      case BackgroundType.randomImage:
        debugLog('Setting WindowEffect.transparent for custom background');
        await Window.setEffect(
          effect: WindowEffect.transparent,
          color: Colors.transparent,
        );
        break;

      case BackgroundType.none:
        debugLog('Setting WindowEffect.solid (no background)');
        await Window.setEffect(
          effect: WindowEffect.solid,
          color: Colors.transparent,
        );
        break;
    }

    
    await applyWindowOpacity(settings.windowOpacity);

    debugLog('Window effect applied successfully');
  } catch (e, stack) {
    debugLog('Failed to apply window effect: $e\n$stack');
  }
}

Future<void> applyWindowOpacity(double opacity) async {
  if (!Platform.isWindows) return;
  
  try {
    await windowManager.setOpacity(opacity.clamp(0.3, 1.0));
    debugLog('Window opacity set to: $opacity');
  } catch (e) {
    debugLog('Failed to set window opacity: $e');
  }
}