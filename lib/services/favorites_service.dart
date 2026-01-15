import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/resource_item.dart';
import 'debug_logger.dart';

class FavoritesService extends ChangeNotifier {
  final String _dataDir;
  final Map<String, ResourceItem> _favorites = {};
  bool _isLoaded = false;

  FavoritesService(this._dataDir);

  List<ResourceItem> get favorites => _favorites.values.toList();
  bool get isLoaded => _isLoaded;

  List<ResourceItem> getFavoritesByType(ResourceType type) {
    return _favorites.values.where((item) => item.type == type).toList();
  }

  bool isFavorite(String id, ResourceSource source) {
    final key = '${source.name}_$id';
    return _favorites.containsKey(key);
  }

  Future<void> addFavorite(ResourceItem item) async {
    final key = '${item.source.name}_${item.id}';
    _favorites[key] = item;
    notifyListeners();
    await _save();
  }

  Future<void> removeFavorite(String id, ResourceSource source) async {
    final key = '${source.name}_$id';
    final item = _favorites.remove(key);
    if (item != null) {
      notifyListeners();
      await _save();
    }
  }

  Future<void> toggleFavorite(ResourceItem item) async {
    if (isFavorite(item.id, item.source)) {
      await removeFavorite(item.id, item.source);
    } else {
      await addFavorite(item);
    }
  }

  Future<void> load() async {
    if (_isLoaded) return;
    
    try {
      final file = File(p.join(_dataDir, 'favorites.json'));
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final items = data['items'] as List? ?? [];
        
        _favorites.clear();
        for (final item in items) {
          final resource = ResourceItem.fromJson(item);
          final key = '${resource.source.name}_${resource.id}';
          _favorites[key] = resource;
        }
      }
    } catch (_) {}
    
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final file = File(p.join(_dataDir, 'favorites.json'));
      await file.parent.create(recursive: true);
      
      final data = {
        'version': 1,
        'items': _favorites.values.map((e) => e.toJson()).toList(),
      };
      
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> clearAll() async {
    _favorites.clear();
    notifyListeners();
    await _save();
  }
}
