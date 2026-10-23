import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mall_map.dart';

class MapStore {
  static const _storageKey = 'asa_saved_maps_v1';
  static const _deletedSampleMapKey = 'asa_sample_map_deleted_v1';
  static const sampleMallMapId = 'sm_seaside_sample';

  Future<bool> isSampleMallMapDeleted() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_deletedSampleMapKey) ?? false;
  }

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
    MallMap? existingMap,
    List<MapFloor> floors = const [],
    required List<MapNode> nodes,
    required List<MapConnection> connections,
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required List<MapCalibrationPoint> calibrationPoints,
  }) async {
    final sourceFloors = floors.isEmpty
        ? [MapFloor(id: 'ground', name: 'Floor 1', imagePath: pickedImagePath)]
        : floors;
    for (final floor in sourceFloors) {
      if (!await File(floor.imagePath).exists()) {
        throw FileSystemException(
          'The floor plan for ${floor.name} could not be found.',
          floor.imagePath,
        );
      }
    }

    final documents = await getApplicationDocumentsDirectory();
    final imagesDirectory = Directory(p.join(documents.path, 'maps'));
    await imagesDirectory.create(recursive: true);

    final id =
        existingMap?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final imageVersion = DateTime.now().microsecondsSinceEpoch;
    final copiedImages = <File>[];
    final savedFloors = <MapFloor>[];
    late final MallMap map;

    try {
      for (var index = 0; index < sourceFloors.length; index++) {
        final floor = sourceFloors[index];
        final extension = p.extension(floor.imagePath).isEmpty
            ? '.jpg'
            : p.extension(floor.imagePath);
        final savedImage = await File(floor.imagePath).copy(
          p.join(
            imagesDirectory.path,
            '${id}_${imageVersion}_$index$extension',
          ),
        );
        copiedImages.add(savedImage);
        savedFloors.add(
          MapFloor(id: floor.id, name: floor.name, imagePath: savedImage.path),
        );
      }
      map = MallMap(
        id: id,
        name: name.trim(),
        imagePath: savedFloors.first.imagePath,
        floors: List.unmodifiable(savedFloors),
        nodes: List.unmodifiable(nodes),
        connections: List.unmodifiable(connections),
        createdAt: existingMap?.createdAt ?? DateTime.now(),
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusMeters,
        calibrationPoints: List.unmodifiable(calibrationPoints),
      );

      final preferences = await SharedPreferences.getInstance();
      final maps = await loadMaps();
      final existingIndex = maps.indexWhere((item) => item.id == map.id);
      if (existingIndex < 0) {
        maps.insert(0, map);
      } else {
        maps[existingIndex] = map;
      }
      final saved = await preferences.setString(
        _storageKey,
        jsonEncode(maps.map((item) => item.toJson()).toList()),
      );
      if (!saved) {
        throw StateError('The map could not be saved on this device.');
      }
    } catch (_) {
      if (!kIsWeb) {
        for (final image in copiedImages) {
          if (await image.exists()) await image.delete();
        }
      }
      rethrow;
    }
    if (existingMap != null && !kIsWeb) {
      final retainedPaths = savedFloors.map((floor) => floor.imagePath).toSet();
      final oldPaths = {
        existingMap.imagePath,
        for (final floor in existingMap.floors) floor.imagePath,
      };
      for (final path in oldPaths.difference(retainedPaths)) {
        final oldImage = File(path);
        if (await oldImage.exists()) {
          try {
            await oldImage.delete();
          } on FileSystemException catch (error) {
            debugPrint('Could not remove replaced floor image: $error');
          }
        }
      }
    }
    return map;
  }

  Future<void> deleteMap(String id) async {
    final preferences = await SharedPreferences.getInstance();
    final maps = await loadMaps();
    final index = maps.indexWhere((map) => map.id == id);
    if (index < 0 && id != sampleMallMapId) return;

    MallMap? removed;
    if (index >= 0) {
      removed = maps.removeAt(index);
      final saved = await preferences.setString(
        _storageKey,
        jsonEncode(maps.map((item) => item.toJson()).toList()),
      );
      if (!saved) throw StateError('The map could not be deleted.');
    }
    if (id == sampleMallMapId) {
      final saved = await preferences.setBool(_deletedSampleMapKey, true);
      if (!saved) throw StateError('The sample map could not be deleted.');
    }

    if (removed != null && !kIsWeb) {
      final imagePaths = {
        removed.imagePath,
        for (final floor in removed.floors) floor.imagePath,
      };
      for (final imagePath in imagePaths) {
        final image = File(imagePath);
        if (await image.exists()) await image.delete();
      }
    }
  }
}
