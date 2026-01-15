import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../widgets/custom_title_bar.dart';
import '../services/config_service.dart';
import '../services/theme_service.dart';
import '../models/config.dart';
import 'home_screen.dart';
import 'accounts_screen.dart';
import 'versions_screen.dart';
import 'download_center_screen.dart';
import 'settings_screen.dart';
import 'about_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    AccountsScreen(),
    VersionsScreen(),
    DownloadCenterScreen(),
    SettingsScreen(),
    AboutScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 600;
    final configService = context.watch<ConfigService>();
    final themeService = context.watch<ThemeService>();
    final settings = configService.settings;

    final destinations = [
      _NavDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: l10n.get('nav_home')),
      _NavDestination(icon: Icons.person_outline, selectedIcon: Icons.person, label: l10n.get('nav_accounts')),
      _NavDestination(icon: Icons.games_outlined, selectedIcon: Icons.games, label: l10n.get('nav_versions')),
      _NavDestination(icon: Icons.download_outlined, selectedIcon: Icons.download, label: l10n.get('nav_downloads')),
      _NavDestination(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: l10n.get('nav_settings')),
      _NavDestination(icon: Icons.info_outline, selectedIcon: Icons.info, label: l10n.get('nav_about')),
    ];

    return Scaffold(
      backgroundColor: settings.backgroundType == BackgroundType.none 
          ? Theme.of(context).colorScheme.surface 
          : Colors.transparent,
      body: Stack(
        children: [
          // Background layer
          _buildBackground(settings, themeService),
          // Main content
          Column(
            children: [
              const CustomTitleBar(),
              Expanded(
                child: Row(
                  children: [
                    if (isWide) _buildNavigationRail(destinations, settings),
                    Expanded(
                      child: _screens[_selectedIndex],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: isWide ? null : NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: destinations.map((d) => NavigationDestination(
          icon: Icon(d.icon),
          selectedIcon: Icon(d.selectedIcon),
          label: d.label,
        )).toList(),
      ),
    );
  }

  Widget _buildBackground(GlobalSettings settings, ThemeService themeService) {
    String? imagePath;
    
    if (settings.backgroundType == BackgroundType.image && settings.customBackgroundPath != null) {
      imagePath = settings.customBackgroundPath;
    } else if (settings.backgroundType == BackgroundType.randomImage && themeService.cachedBackgroundPath != null) {
      imagePath = themeService.cachedBackgroundPath;
    }
    
    if (imagePath == null || settings.backgroundType == BackgroundType.none) {
      return const SizedBox.shrink();
    }
    
    final file = File(imagePath);
    if (!file.existsSync()) {
      return const SizedBox.shrink();
    }
    
    // Use backgroundVersion as key to force rebuild when image changes
    return Container(
      key: ValueKey('bg_${themeService.backgroundVersion}_$imagePath'),
      decoration: BoxDecoration(
        image: DecorationImage(
          image: FileImage(file),
          fit: BoxFit.cover,
        ),
      ),
      child: settings.backgroundBlur > 0
          ? BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: settings.backgroundBlur,
                sigmaY: settings.backgroundBlur,
              ),
              child: Container(color: Colors.transparent),
            )
          : null,
    );
  }

  Widget _buildNavigationRail(List<_NavDestination> destinations, GlobalSettings settings) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasCustomBackground = settings.backgroundType != BackgroundType.none;
    final surfaceOpacity = hasCustomBackground ? 0.85 : 1.0;
    
    // MD3 Pad style - fixed width navigation rail
    return Container(
      width: 80,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: surfaceOpacity),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: destinations.length,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemBuilder: (context, index) {
                final dest = destinations[index];
                final isSelected = _selectedIndex == index;
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: InkWell(
                    onTap: () => setState(() => _selectedIndex = index),
                    borderRadius: BorderRadius.circular(16),
                    hoverColor: colorScheme.onSurface.withValues(alpha: 0.08),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? colorScheme.secondaryContainer.withValues(alpha: surfaceOpacity)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            isSelected ? dest.selectedIcon : dest.icon,
                            size: 24,
                            color: isSelected 
                                ? colorScheme.onSecondaryContainer 
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dest.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected 
                                ? colorScheme.onSurface 
                                : colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
