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
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      timeLimit: Duration(seconds: 15),
    ),
  );

  @override
  Stream<Position> watchPosition() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    ),
  );
}

class RelativeMovementUpdate {
  const RelativeMovementUpdate({
    required this.mapOffset,
    required this.shouldAdvanceBaseline,
  });

  final Offset? mapOffset;
  final bool shouldAdvanceBaseline;
}

RelativeMovementUpdate estimateRelativeMovement({
  required Position previous,
  required Position current,
  required List<MapCalibrationPoint> calibrationPoints,
}) {
  final elapsedSeconds =
      current.timestamp
          .difference(previous.timestamp)
          .inMilliseconds
          .clamp(0, 3000) /
      1000;
  final reliableSpeedAndHeading =
      current.hasSpeed &&
      current.hasHeading &&
      current.speed >= 0.3 &&
      (!current.hasSpeedAccuracy || current.speedAccuracy <= 3.5) &&
      (!current.hasHeadingAccuracy || current.headingAccuracy <= 45);

  if (elapsedSeconds > 0 && reliableSpeedAndHeading) {
    final distance = (current.speed * elapsedSeconds * 2.0)
        .clamp(0.0, 6.0)
        .toDouble();
    final heading = current.heading * math.pi / 180;
    return RelativeMovementUpdate(
      mapOffset: _correctMovementOrientation(
        mapOffsetForMovement(
          eastMeters: distance * math.sin(heading),
          northMeters: distance * math.cos(heading),
          calibrationPoints: calibrationPoints,
        ),
      ),
      shouldAdvanceBaseline: true,
    );
  }

  // Indoor GPS often has no speed/course. Use only the change between fixes,
  // never project the current absolute coordinates onto the floor plan.
  final meanLatitude = (previous.latitude + current.latitude) / 2;
  final eastMeters =
      (current.longitude - previous.longitude) *
      111320 *
      math.cos(meanLatitude * math.pi / 180);
  final northMeters = (current.latitude - previous.latitude) * 111320;
  final distance = math.sqrt(
    eastMeters * eastMeters + northMeters * northMeters,
  );
  final accuracy = [
    previous.accuracy,
    current.accuracy,
  ].where((value) => value > 0).fold<double>(0, math.max);
  final minimumMovement = (accuracy * 0.04).clamp(0.35, 1.0).toDouble();

  if (distance < minimumMovement) {
    return const RelativeMovementUpdate(
      mapOffset: null,
      shouldAdvanceBaseline: false,
    );
  }
  if (distance > 10) {
    return const RelativeMovementUpdate(
      mapOffset: null,
      shouldAdvanceBaseline: true,
    );
  }

  return RelativeMovementUpdate(
    mapOffset: _correctMovementOrientation(
      mapOffsetForMovement(
        eastMeters: eastMeters * 1.8,
        northMeters: northMeters * 1.8,
        calibrationPoints: calibrationPoints,
      ),
    ),
    shouldAdvanceBaseline: true,
  );
}

Offset? _correctMovementOrientation(Offset? movement) =>
    movement == null ? null : Offset(-movement.dy, movement.dx);

bool isInsideGeofence({
  required double latitude,
  required double longitude,
  required double centerLatitude,
  required double centerLongitude,
  required double radiusMeters,
  double toleranceMeters = 0,
}) =>
    Geolocator.distanceBetween(
      latitude,
      longitude,
      centerLatitude,
      centerLongitude,
    ) <=
    radiusMeters + toleranceMeters;

bool hasUsableLocationCalibration(List<MapCalibrationPoint> calibrationPoints) {
  if (calibrationPoints.length >= 2) return true;
  if (calibrationPoints.length != 1) return false;
  final point = calibrationPoints.single;
  return point.floorWidthMeters != null &&
      point.floorWidthMeters! > 0 &&
      point.floorHeightMeters != null &&
      point.floorHeightMeters! > 0;
}

Offset clampLocationToMap(Offset location) => Offset(
  location.dx.clamp(0.0, 1.0).toDouble(),
  location.dy.clamp(0.0, 1.0).toDouble(),
);

Offset? projectLocationToMap({
  required double latitude,
  required double longitude,
  required List<MapCalibrationPoint> calibrationPoints,
}) {
  if (calibrationPoints.isEmpty) return null;
  final first = calibrationPoints[0];
  if (calibrationPoints.length == 1) {
    final width = first.floorWidthMeters;
    final height = first.floorHeightMeters;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    final longitudeScale = 111320 * math.cos(first.latitude * math.pi / 180);
    const latitudeScale = 111320.0;
    final east = (longitude - first.longitude) * longitudeScale;
    final north = (latitude - first.latitude) * latitudeScale;
    final bearing = (first.bearingDegrees ?? 0) * math.pi / 180;
    final mapEast = east * math.cos(bearing) - north * math.sin(bearing);
    final mapSouth = -east * math.sin(bearing) - north * math.cos(bearing);
    return Offset(first.x + mapEast / width, first.y + mapSouth / height);
  }
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

Offset? mapOffsetForMovement({
  required double eastMeters,
  required double northMeters,
  required List<MapCalibrationPoint> calibrationPoints,
}) {
  if (calibrationPoints.isEmpty) return null;
  final first = calibrationPoints.first;
  if (calibrationPoints.length == 1) {
    final width = first.floorWidthMeters;
    final height = first.floorHeightMeters;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    final bearing = (first.bearingDegrees ?? 0) * math.pi / 180;
    return Offset(
      (eastMeters * math.cos(bearing) - northMeters * math.sin(bearing)) /
          width,
      (-eastMeters * math.sin(bearing) - northMeters * math.cos(bearing)) /
          height,
    );
  }

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
  return Offset(
    scaleA * eastMeters - scaleB * northMeters,
    scaleB * eastMeters + scaleA * northMeters,
  );
}

double? mapDistanceMeters({
  required Offset from,
  required Offset to,
  required List<MapCalibrationPoint> calibrationPoints,
}) {
  if (calibrationPoints.isEmpty) return null;
  // Relative movement is rotated 90° clockwise to align with this floor plan.
  final dx = to.dy - from.dy;
  final dy = from.dx - to.dx;
  final first = calibrationPoints.first;
  if (calibrationPoints.length == 1) {
    final width = first.floorWidthMeters;
    final height = first.floorHeightMeters;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return math.sqrt(math.pow(dx * width, 2) + math.pow(dy * height, 2));
  }

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
  final scaleDenominator = scaleA * scaleA + scaleB * scaleB;
  if (scaleDenominator < 0.0000000001) return null;
  final east = (scaleA * dx + scaleB * dy) / scaleDenominator;
  final north = (-scaleB * dx + scaleA * dy) / scaleDenominator;
  return math.sqrt(east * east + north * north);
}

double? distanceToMapPointMeters({
  required double latitude,
  required double longitude,
  required double mapX,
  required double mapY,
  required List<MapCalibrationPoint> calibrationPoints,
}) {
  if (calibrationPoints.isEmpty) return null;
  if (calibrationPoints.length == 1) {
    final first = calibrationPoints.first;
    final width = first.floorWidthMeters;
    final height = first.floorHeightMeters;
    final projected = projectLocationToMap(
      latitude: latitude,
      longitude: longitude,
      calibrationPoints: calibrationPoints,
    );
    if (width == null || height == null || projected == null) return null;
    return math.sqrt(
      math.pow((projected.dx - mapX) * width, 2) +
          math.pow((projected.dy - mapY) * height, 2),
    );
  }
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
