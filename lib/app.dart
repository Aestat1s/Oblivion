import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'screens/main_screen.dart';
import 'screens/bootstrap_screen.dart';
import 'services/config_service.dart';
import 'services/theme_service.dart';
import 'models/config.dart';
import 'l10n/app_localizations.dart';

class OblivionApp extends StatelessWidget {
  const OblivionApp({super.key});

  @override
  Widget build(BuildContext context) {
    final configService = context.watch<ConfigService>();
    final themeService = context.watch<ThemeService>();
    final settings = configService.settings;
    final themeMode = settings.themeMode;
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    
    final locale = settings.language == 'zh' 
        ? const Locale('zh') 
        : const Locale('en');

    
    final seedColor = themeService.seedColor ?? const Color(0xFF6750A4);
    
    
    final hasCustomBackground = settings.backgroundType != BackgroundType.none;
    
    
    final surfaceOpacity = hasCustomBackground ? 0.85 : 1.0;
    
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: isDark ? Brightness.dark : Brightness.light,
    );

    return MaterialApp(
      title: 'Oblivion Launcher',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('zh')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: hasCustomBackground ? Colors.transparent : null,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: colorScheme.surfaceContainerHigh.withValues(alpha: surfaceOpacity),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: surfaceOpacity),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: colorScheme.surfaceContainerHigh.withValues(alpha: surfaceOpacity),
        ),
        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: Colors.transparent,
          indicatorColor: colorScheme.primaryContainer.withValues(alpha: surfaceOpacity),
          selectedIconTheme: IconThemeData(color: colorScheme.onPrimaryContainer),
          unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
          labelType: NavigationRailLabelType.all,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: colorScheme.surfaceContainerLow.withValues(alpha: surfaceOpacity),
        ),
      ),
      themeMode: themeMode,
      home: settings.isFirstRun ? const BootstrapScreen() : const MainScreen(),
    );
  }
}
