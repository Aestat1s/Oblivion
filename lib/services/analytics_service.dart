import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';

class AnalyticsService {
  static const String _baseUrl = 'https://umami.aestat1s.com/api/send';
  
  static const String _websiteId = String.fromEnvironment(
    'UMAMI_ID',
    defaultValue: 'd2e161ac-ea20-4e95-93bd-4c1b9fc415a9',
  );
  static const String _hostname = 'oblivion.aestat1s.com';
  
  
  String _screenSize = '';
  Timer? _heartbeatTimer;
  String? _currentPath;
  
  Future<void> init() async {
    try {
      final size = await windowManager.getSize();
      _screenSize = '${size.width.toInt()}x${size.height.toInt()}';
    } catch (e) {
      _screenSize = '1280x800'; 
    }
    _startHeartbeat();
  }

  void dispose() {
    _heartbeatTimer?.cancel();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    
    
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      
      _sendPayload(
        url: '/heartbeat', 
        title: 'heartbeat',
        name: 'heartbeat',
      );
    });
  }

  Future<void> trackPageView(String path, String title) async {
    await _sendPayload(
      url: path,
      title: title,
      referrer: _currentPath,
    );
    _currentPath = path;
  }

  Future<void> trackEvent(String eventName, {Map<String, dynamic>? data}) async {
    await _sendPayload(
      url: _currentPath ?? '/event', 
      title: eventName,
      name: eventName,
      data: data,
      referrer: _currentPath,
    );
  }

  Future<void> _sendPayload({
    required String url,
    required String title,
    String? name,
    Map<String, dynamic>? data,
    String? referrer,
  }) async {
    try {
      
      try {
         final size = await windowManager.getSize();
         _screenSize = '${size.width.toInt()}x${size.height.toInt()}';
      } catch (_) {}

      final payload = {
        'website': _websiteId,
        'hostname': _hostname,
        'screen': _screenSize,
        'language': Platform.localeName,
        'title': title,
        'url': url,
        if (referrer != null) 'referrer': referrer,
        if (name != null) 'name': name,
        if (data != null) 'data': data,
      };

      final body = {
        'payload': payload,
        'type': 'event',
      };

      await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Oblivion/${Platform.operatingSystem}', 
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      
      debugPrint('Analytics error: $e');
    }
  }
}
