import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'debug_logger.dart';

class SystemColorService {
  static const _channel = MethodChannel('com.oblivion.launcher/system_color');
  static Color? _cachedColor;
  static bool _hasFetched = false;

  static Future<Color?> getSystemAccentColor() async {
    if (!Platform.isWindows) return null;

    if (_hasFetched && _cachedColor != null) {
      return _cachedColor;
    }

    try {
      debugLog('Fetching system accent color via platform channel...');
      final result = await _channel.invokeMethod<dynamic>('getAccentColor');
      debugLog('System color result: $result (type: ${result.runtimeType})');
      
      if (result != null) {
        int colorValue;
        if (result is int) {
          colorValue = result;
        } else {
          colorValue = (result as num).toInt();
        }
        
        _cachedColor = Color(colorValue | 0xFF000000);
        _hasFetched = true;
        debugLog('Parsed system color: $_cachedColor');
        return _cachedColor;
      }
    } catch (e) {
      debugLog('Failed to get system accent color: $e');
    }

    return null;
  }

  static void clearCache() {
    _cachedColor = null;
    _hasFetched = false;
  }
}
