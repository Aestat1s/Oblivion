import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/config.dart';
import 'system_color_service.dart';
import 'debug_logger.dart';

class ThemeService extends ChangeNotifier {
  Color? _seedColor;
  Color? _backgroundExtractedColor;
  String? _cachedBackgroundPath;
  bool _isLoadingBackground = false;
  bool _isExtractingColor = false;
  int _backgroundVersion = 0;

  Color? get seedColor => _seedColor;
  Color? get backgroundExtractedColor => _backgroundExtractedColor;
  String? get cachedBackgroundPath => _cachedBackgroundPath;
  bool get isLoadingBackground => _isLoadingBackground;
  bool get isExtractingColor => _isExtractingColor;
  int get backgroundVersion => _backgroundVersion;

  Future<void> initialize(GlobalSettings settings) async {
    debugLog('ThemeService initializing...');
    await _loadCachedBackground();
    await updateThemeColor(settings);
    debugLog('ThemeService initialized, seedColor: $_seedColor');
  }

  Future<void> updateThemeColor(GlobalSettings settings) async {
    debugLog('updateThemeColor called, enableCustomColor: ${settings.enableCustomColor}, source: ${settings.themeColorSource}');
    
    if (!settings.enableCustomColor) {
      _seedColor = null;
      notifyListeners();
      return;
    }
    
    Color? newColor;

    switch (settings.themeColorSource) {
      case ThemeColorSource.system:
        debugLog('Getting system accent color...');
        newColor = await _getSystemAccentColor();
        debugLog('System accent color result: $newColor');
        break;
        
      case ThemeColorSource.customBackground:
        debugLog('Getting color from background...');
        if (settings.backgroundType == BackgroundType.image && settings.customBackgroundPath != null) {
          newColor = await _extractColorFromImage(settings.customBackgroundPath!);
        } else if (settings.backgroundType == BackgroundType.randomImage && _cachedBackgroundPath != null) {
          newColor = await _extractColorFromImage(_cachedBackgroundPath!);
        }
        if (newColor == null && _backgroundExtractedColor != null) {
          newColor = _backgroundExtractedColor;
        }
        break;
        
      case ThemeColorSource.manual:
        if (settings.customThemeColor != null) {
          newColor = Color(settings.customThemeColor!);
        }
        break;
    }

    if (newColor != null) {
      _seedColor = newColor;
      notifyListeners();
      debugLog('Theme color updated to: $newColor');
    }
  }

  Future<void> extractColorFromCurrentBackground(GlobalSettings settings) async {
    if (_isExtractingColor) return;
    
    String? imagePath;
    
    if (settings.backgroundType == BackgroundType.image && settings.customBackgroundPath != null) {
      imagePath = settings.customBackgroundPath;
    } else if (settings.backgroundType == BackgroundType.randomImage && _cachedBackgroundPath != null) {
      imagePath = _cachedBackgroundPath;
    }
    
    if (imagePath != null) {
      _isExtractingColor = true;
      notifyListeners();
      
      try {
        _backgroundExtractedColor = await _extractColorFromImage(imagePath);
        debugLog('Background extracted color: $_backgroundExtractedColor');
        
        if (settings.enableCustomColor && settings.themeColorSource == ThemeColorSource.customBackground) {
          _seedColor = _backgroundExtractedColor;
        }
      } finally {
        _isExtractingColor = false;
        notifyListeners();
      }
    }
  }

  Future<Color?> _getSystemAccentColor() async {
    try {
      return await SystemColorService.getSystemAccentColor();
    } catch (e) {
      debugLog('Error getting system accent color: $e');
      return null;
    }
  }

  Future<Color?> _extractColorFromImage(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        debugLog('Image file does not exist: $imagePath');
        return null;
      }

      debugLog('Extracting color from image: $imagePath');
      
      final imageProvider = FileImage(file);
      
      final colorScheme = await ColorScheme.fromImageProvider(
        provider: imageProvider,
        brightness: Brightness.dark,
      );
      
      final extractedColor = colorScheme.primary;
      debugLog('Extracted color: $extractedColor');
      
      return extractedColor;
    } catch (e, stack) {
      debugLog('Failed to extract color from image: $e\n$stack');
      return null;
    }
  }

  Future<void> fetchRandomBackground(GlobalSettings settings) async {
    if (_isLoadingBackground) return;
    
    _isLoadingBackground = true;
    notifyListeners();

    try {
      final apiUrl = settings.randomImageApi;
      
      if (apiUrl == null || apiUrl.isEmpty) {
        throw Exception('API URL not configured');
      }

      debugLog('Fetching random background from: $apiUrl');
      final response = await http.get(Uri.parse(apiUrl));
      
      if (response.statusCode == 200) {
        final appDir = await getApplicationSupportDirectory();
        final cacheDir = Directory(p.join(appDir.path, 'backgrounds'));
        await cacheDir.create(recursive: true);

        final cachedFile = File(p.join(cacheDir.path, 'random_bg.jpg'));
        await cachedFile.writeAsBytes(response.bodyBytes);
        
        _cachedBackgroundPath = cachedFile.path;
        _backgroundVersion++;
        debugLog('Random background saved to: $_cachedBackgroundPath (version: $_backgroundVersion)');
        
        imageCache.clear();
        imageCache.clearLiveImages();
        
        await extractColorFromCurrentBackground(settings);
        
        notifyListeners();
      } else {
        debugLog('Failed to fetch random background: ${response.statusCode}');
      }
    } catch (e) {
      debugLog('Failed to fetch random background: $e');
    } finally {
      _isLoadingBackground = false;
      notifyListeners();
    }
  }

  Future<void> _loadCachedBackground() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final cachedFile = File(p.join(appDir.path, 'backgrounds', 'random_bg.jpg'));
      
      if (await cachedFile.exists()) {
        _cachedBackgroundPath = cachedFile.path;
        debugLog('Loaded cached background: $_cachedBackgroundPath');
      }
    } catch (e) {
      debugLog('Failed to load cached background: $e');
    }
  }

  Future<void> clearCachedBackground() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final cachedFile = File(p.join(appDir.path, 'backgrounds', 'random_bg.jpg'));
      
      if (await cachedFile.exists()) {
        await cachedFile.delete();
      }
      
      _cachedBackgroundPath = null;
      _backgroundExtractedColor = null;
      notifyListeners();
    } catch (e) {
      debugLog('Failed to clear cached background: $e');
    }
  }
}
