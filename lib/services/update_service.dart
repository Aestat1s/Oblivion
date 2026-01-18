import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final String version;
  final String changelog;
  final String downloadUrl;
  final DateTime updatedAt;

  UpdateInfo({
    required this.version,
    required this.changelog,
    required this.downloadUrl,
    required this.updatedAt,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] ?? '0.0.0',
      changelog: json['changelog'] ?? '',
      downloadUrl: json['downloadUrl'] ?? '',
      updatedAt: json['updatedAt'] != null 
          ? DateTime.tryParse(json['updatedAt']) ?? DateTime.now() 
          : DateTime.now(),
    );
  }
}

class UpdateService extends ChangeNotifier {
  static const String _baseUrl = 'https://ob-api.aestat1s.com';
  
  UpdateInfo? _latestUpdate;
  String? _announcement;

  UpdateInfo? get latestUpdate => _latestUpdate;
  String? get announcement => _announcement;
  
  bool _hasChecked = false;
  bool _hasFetchedAnnouncement = false;
  bool _hasShownDialog = false;

  bool get hasChecked => _hasChecked;
  bool get hasShownDialog => _hasShownDialog;

  void markDialogShown() {
    _hasShownDialog = true;
    notifyListeners();
  }

  Future<UpdateInfo?> checkUpdate({bool force = false}) async {
    if (_hasChecked && !force) return _latestUpdate;

    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/version/latest'))
          .timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final latest = UpdateInfo.fromJson(data);
        
        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;
        
        if (_isNewer(latest.version, currentVersion)) {
          _latestUpdate = latest;
          notifyListeners();
          return latest;
        }
      }
    } catch (e) {
      debugPrint('Failed to check update: $e');
    } finally {
      _hasChecked = true;
    }
    return _latestUpdate;
  }

  Future<String?> fetchAnnouncement({bool force = false}) async {
    if (_hasFetchedAnnouncement && !force) return _announcement;

    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/announcement'))
          .timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        _announcement = data['content'];
        notifyListeners();
        return _announcement;
      }
    } catch (e) {
      debugPrint('Failed to fetch announcement: $e');
    } finally {
      _hasFetchedAnnouncement = true;
    }
    return _announcement;
  }

  bool _isNewer(String latest, String current) {
    if (latest == current) return false;
    try {
      final lParts = latest.split('.').map(int.parse).toList();
      final cParts = current.split('+')[0].split('.').map(int.parse).toList();
      
      for (int i = 0; i < lParts.length && i < cParts.length; i++) {
        if (lParts[i] > cParts[i]) return true;
        if (lParts[i] < cParts[i]) return false;
      }
      return lParts.length > cParts.length;
    } catch (e) {
      return false;
    }
  }

  Future<void> performUpdate(String downloadUrl) async {
    final uri = Uri.parse(downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
