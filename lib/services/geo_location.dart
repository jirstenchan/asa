import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/mall_map.dart';

abstract interface class LocationProvider {
  Future<void> ensurePermission();
  Future<Position> getCurrentPosition();
  Stream<Position> watchPosition();
}

class GeolocatorLocationProvider implements LocationProvider {
  const GeolocatorLocationProvider();

  @override
  Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on location services to navigate.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission is required for live navigation.');
    }
  }

  @override
  Future<Position> getCurrentPosition() => Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );

  @override
  Stream<Position> watchPosition() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    ),
  );
}

bool isInsideGeofence({
  required double latitude,
  required double longitude,
  required double centerLatitude,
  required double centerLongitude,
  required double radiusMeters,
}) =>
    Geolocator.distanceBetween(
      latitude,
      longitude,
      centerLatitude,
      centerLongitude,
    ) <=
    radiusMeters;

Offset? projectLocationToMap({
  required double latitude,
  required double longitude,
  required List<MapCalibrationPoint> calibrationPoints,
}) {
  if (calibrationPoints.length < 2) return null;
  final first = calibrationPoints[0];
  final second = calibrationPoints[1];
  final longitudeScale = 111320 * math.cos(first.latitude * math.pi / 180);
  const latitudeScale = 111320.0;
  final anchorEast = (second.longitude - first.longitude) * longitudeScale;
  final anchorNorth = (second.latitude - first.latitude) * latitudeScale;
  final denominator = anchorEast * anchorEast + anchorNorth * anchorNorth;
  if (denominator < 0.01) return null;

  final mapX = second.x - first.x;
  final mapY = second.y - first.y;
  final scaleA = (mapX * anchorEast + mapY * anchorNorth) / denominator;
  final scaleB = (mapY * anchorEast - mapX * anchorNorth) / denominator;
  final east = (longitude - first.longitude) * longitudeScale;
  final north = (latitude - first.latitude) * latitudeScale;
  return Offset(
    first.x + scaleA * east - scaleB * north,
    first.y + scaleB * east + scaleA * north,
  );
}

double? distanceToMapPointMeters({
  required double latitude,
  required double longitude,
  required double mapX,
  required double mapY,
  required List<MapCalibrationPoint> calibrationPoints,
}) {
  if (calibrationPoints.length < 2) return null;
  final first = calibrationPoints[0];
  final second = calibrationPoints[1];
  final projected = projectLocationToMap(
    latitude: latitude,
    longitude: longitude,
    calibrationPoints: calibrationPoints,
  );
  if (projected == null) return null;
  final mapDistance = math.sqrt(
    math.pow(second.x - first.x, 2) + math.pow(second.y - first.y, 2),
  );
  if (mapDistance < 0.000001) return null;
  final geoDistance = Geolocator.distanceBetween(
    first.latitude,
    first.longitude,
    second.latitude,
    second.longitude,
  );
  return math.sqrt(
        math.pow(projected.dx - mapX, 2) + math.pow(projected.dy - mapY, 2),
      ) *
      geoDistance /
      mapDistance;
}
