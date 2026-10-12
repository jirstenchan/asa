import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mall_map.dart';

class MapStore {
  static const _storageKey = 'asa_saved_maps_v1';

  Future<List<MallMap>> loadMaps() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) return [];
    final decoded = jsonDecode(encoded) as List<dynamic>;
    return decoded
        .map((item) => MallMap.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<MallMap> saveMap({
    required String name,
    required String pickedImagePath,
    required List<MapNode> nodes,
    required List<MapConnection> connections,
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required List<MapCalibrationPoint> calibrationPoints,
  }) async {
    final source = File(pickedImagePath);
    if (!await source.exists()) {
      throw FileSystemException('The selected map image could not be found.');
    }

    final documents = await getApplicationDocumentsDirectory();
    final imagesDirectory = Directory(p.join(documents.path, 'maps'));
    await imagesDirectory.create(recursive: true);

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final extension = p.extension(pickedImagePath).isEmpty
        ? '.jpg'
        : p.extension(pickedImagePath);
    final savedImage = await source.copy(
      p.join(imagesDirectory.path, '$id$extension'),
    );

    final map = MallMap(
      id: id,
      name: name.trim(),
      imagePath: savedImage.path,
      nodes: List.unmodifiable(nodes),
      connections: List.unmodifiable(connections),
      createdAt: DateTime.now(),
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      calibrationPoints: List.unmodifiable(calibrationPoints),
    );

    try {
      final preferences = await SharedPreferences.getInstance();
      final maps = await loadMaps();
      maps.insert(0, map);
      final saved = await preferences.setString(
        _storageKey,
        jsonEncode(maps.map((item) => item.toJson()).toList()),
      );
      if (!saved) throw StateError('The map could not be saved on this device.');
    } catch (_) {
      if (!kIsWeb) await savedImage.delete();
      rethrow;
    }
    return map;
  }

  Future<void> deleteMap(String id) async {
    final preferences = await SharedPreferences.getInstance();
    final maps = await loadMaps();
    final index = maps.indexWhere((map) => map.id == id);
    if (index < 0) return;

    final removed = maps.removeAt(index);
    final saved = await preferences.setString(
      _storageKey,
      jsonEncode(maps.map((item) => item.toJson()).toList()),
    );
    if (!saved) throw StateError('The map could not be deleted.');

    final image = File(removed.imagePath);
    if (!kIsWeb && await image.exists()) await image.delete();
  }
}
