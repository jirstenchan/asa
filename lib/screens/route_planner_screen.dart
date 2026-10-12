import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/mall_map.dart';
import '../services/geo_location.dart';
import '../services/route_finder.dart';
import '../widgets/map_preview.dart';

class RoutePlannerScreen extends StatefulWidget {
  const RoutePlannerScreen({
    super.key,
    required this.mallName,
    required this.nodes,
    required this.connections,
    this.imagePath,
    this.latitude,
    this.longitude,
    this.radiusMeters,
    this.calibrationPoints = const [],
    this.locationProvider,
  });

  final String mallName;
  final String? imagePath;
  final List<MapNode> nodes;
  final List<MapConnection> connections;
  final double? latitude;
  final double? longitude;
  final double? radiusMeters;
  final List<MapCalibrationPoint> calibrationPoints;
  final LocationProvider? locationProvider;

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  late final LocationProvider _locationProvider;
  StreamSubscription<Position>? _locationSubscription;
  String? _originId;
  String? _destinationId;
  List<MapNode>? _route;
  bool _isNavigating = false;
  bool _hasArrived = false;
  bool _isStarting = false;
  bool? _isInsideMall;
  Position? _position;
  String? _locationStatus;

  @override
  void initState() {
    super.initState();
    _locationProvider =
        widget.locationProvider ?? const GeolocatorLocationProvider();
  }

  @override
  void dispose() {
    unawaited(_locationSubscription?.cancel());
    super.dispose();
  }

  void _clearRoute() {
    _stopLocationTracking();
    _route = null;
    _isNavigating = false;
    _hasArrived = false;
    _position = null;
    _isInsideMall = null;
    _locationStatus = null;
    _isStarting = false;
  }

  void _stopLocationTracking() {
    final subscription = _locationSubscription;
    _locationSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _planRoute() {
    if (widget.nodes.isEmpty) {
      _showMessage('This map has no labeled spots yet.');
      return;
    }
    if (_originId == null || _destinationId == null) {
      _showMessage('Choose where you are and where you want to go.');
      return;
    }
    if (_originId == _destinationId) {
      _showMessage('Choose a destination different from your current spot.');
      return;
    }
    final route = findRoute(
      nodes: widget.nodes,
      connections: widget.connections,
      from: _originId!,
      to: _destinationId!,
    );
    if (route == null) {
      _showMessage(
        'There is no path between those spots. Add a connection in the map editor.',
      );
      return;
    }
    setState(() {
      _route = route;
      _isNavigating = false;
      _hasArrived = false;
    });
  }

  Future<void> _startNavigation() async {
    if (_route == null) return;
    final latitude = widget.latitude;
    final longitude = widget.longitude;
    final radius = widget.radiusMeters;
    if (latitude == null || longitude == null || radius == null) {
      _showMessage('This map needs mall GPS coordinates and a radius.');
      return;
    }
    if (widget.calibrationPoints.length < 2) {
      _showMessage('Add two GPS reference points to this floor plan first.');
      return;
    }
    setState(() {
      _isStarting = true;
      _locationStatus = 'Checking your location…';
    });
    try {
      await _locationProvider.ensurePermission();
      final position = await _locationProvider.getCurrentPosition();
      if (!mounted) return;
      if (!_isPositionInsideMall(position)) {
        setState(() {
          _isStarting = false;
          _isInsideMall = false;
          _position = position;
          _locationStatus =
              'You appear to be outside the ${radius.round()} m mall area.';
        });
        return;
      }
      setState(() {
        _isStarting = false;
        _isNavigating = true;
      });
      _updateLocation(position);
      _locationSubscription = _locationProvider.watchPosition().listen(
        _updateLocation,
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _isNavigating = false;
            _locationStatus = 'Live location updates stopped: $error';
          });
          _stopLocationTracking();
        },
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _isStarting = false;
          _isNavigating = false;
          _locationStatus = error.toString();
        });
        _showMessage('Could not start live location tracking: $error');
      }
    }
  }

  bool _isPositionInsideMall(Position position) {
    final centerLatitude = widget.latitude;
    final centerLongitude = widget.longitude;
    final radius = widget.radiusMeters;
    if (centerLatitude == null ||
        centerLongitude == null ||
        radius == null) {
      return false;
    }
    return isInsideGeofence(
      latitude: position.latitude,
      longitude: position.longitude,
      centerLatitude: centerLatitude,
      centerLongitude: centerLongitude,
      radiusMeters: radius,
    );
  }

  void _updateLocation(Position position) {
    if (!mounted) return;
    final inside = _isPositionInsideMall(position);
    final location = inside
        ? projectLocationToMap(
            latitude: position.latitude,
            longitude: position.longitude,
            calibrationPoints: widget.calibrationPoints,
          )
        : null;
    setState(() {
      _position = position;
      _isInsideMall = inside;
      if (!inside) _isNavigating = false;
      _locationStatus = inside
          ? location == null
                ? 'GPS is inside the mall, but outside the calibrated map area.'
                : 'Live location · about ${position.accuracy.round()} m accuracy'
          : 'You appear to be outside the ${widget.radiusMeters!.round()} m mall area.';
    });
    if (!inside) {
      _stopLocationTracking();
      return;
    }

    final destination = _route?.last;
    if (destination != null) {
      final distance = distanceToMapPointMeters(
        latitude: position.latitude,
        longitude: position.longitude,
        mapX: destination.x,
        mapY: destination.y,
        calibrationPoints: widget.calibrationPoints,
      );
      if (distance != null && distance <= 12 && !_hasArrived) {
        setState(() {
          _isNavigating = false;
          _hasArrived = true;
          _locationStatus = 'You are near ${destination.label}.';
        });
        _stopLocationTracking();
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final routeIds = route?.map((node) => node.id).toList();
    final position = _position;
    final deviceLocation = position == null || _isInsideMall != true
        ? null
        : projectLocationToMap(
            latitude: position.latitude,
            longitude: position.longitude,
            calibrationPoints: widget.calibrationPoints,
          );
    final visibleLocation =
        deviceLocation != null &&
            deviceLocation.dx >= 0 &&
            deviceLocation.dx <= 1 &&
            deviceLocation.dy >= 0 &&
            deviceLocation.dy <= 1
        ? deviceLocation
        : null;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
        ),
        title: Text(
          widget.mallName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            const Text(
              'Plan your route',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            const Text(
              'Choose where you are in the mall, then where you want to go.',
              style: TextStyle(color: Color(0xFF737B81), height: 1.4),
            ),
            const SizedBox(height: 18),
            _PlaceSelector(
              label: 'WHERE ARE YOU NOW?',
              hint: 'Select your current spot',
              icon: Icons.my_location_rounded,
              value: _originId,
              nodes: widget.nodes,
              onChanged: (id) {
                setState(() {
                  _originId = id;
                  _clearRoute();
                });
              },
            ),
            const SizedBox(height: 12),
            _PlaceSelector(
              label: 'WHERE DO YOU WANT TO GO?',
              hint: 'Select your destination',
              icon: Icons.location_on_outlined,
              value: _destinationId,
              nodes: widget.nodes,
              onChanged: (id) {
                setState(() {
                  _destinationId = id;
                  _clearRoute();
                });
              },
            ),
            const SizedBox(height: 16),
            MapPreview(
              height: 340,
              imagePath: widget.imagePath,
              nodes: widget.nodes,
              connections: widget.connections,
              routeNodeIds: routeIds,
              currentNodeId: _isNavigating || _hasArrived
                  ? null
                  : _originId,
              destinationNodeId: _destinationId,
              deviceLocation: visibleLocation,
              emptyLabel: '',
              showControls: true,
            ),
            const SizedBox(height: 14),
            if (route == null)
              _RouteTip(nodeCount: widget.nodes.length)
            else if (_isNavigating || _hasArrived || _locationStatus != null)
              _NavigationInstructions(
                destination: route.last.label,
                hasArrived: _hasArrived,
                isNavigating: _isNavigating,
                isStarting: _isStarting,
                status: _locationStatus,
                outsideMall: _isInsideMall == false,
              )
            else
              _RouteSummary(route: route),
            const SizedBox(height: 16),
            SizedBox(
              height: 53,
              child: FilledButton(
                onPressed: route == null
                    ? _planRoute
                    : _isNavigating
                    ? null
                    : _hasArrived
                    ? null
                    : _isStarting
                    ? null
                    : _startNavigation,
                child: Text(
                  route == null
                      ? 'Show route'
                      : _isNavigating
                      ? 'Navigation in progress'
                      : _hasArrived
                      ? "You've arrived"
                      : _isStarting
                      ? 'Checking your location…'
                      : 'Start navigation',
                ),
              ),
            ),
            if (route != null) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => setState(_clearRoute),
                  child: Text(
                    _isNavigating || _hasArrived
                        ? 'End navigation'
                        : 'Plan another route',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlaceSelector extends StatelessWidget {
  const _PlaceSelector({
    required this.label,
    required this.hint,
    required this.icon,
    required this.value,
    required this.nodes,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final IconData icon;
  final String? value;
  final List<MapNode> nodes;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: .55,
          fontWeight: FontWeight.w800,
          color: Color(0xFF555D63),
        ),
      ),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, size: 20),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 11,
          ),
        ),
        items: nodes
            .map(
              (node) => DropdownMenuItem<String>(
                value: node.id,
                child: Text(node.label, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: nodes.isEmpty ? null : onChanged,
      ),
    ],
  );
}

class _RouteTip extends StatelessWidget {
  const _RouteTip({required this.nodeCount});

  final int nodeCount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F6F7),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            nodeCount < 2
                ? 'This map needs at least two labeled spots before you can plan a route.'
                : 'Select your starting place and destination above. We’ll find a connected path through the map.',
            style: const TextStyle(
              color: Color(0xFF68727A),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.route});

  final List<MapNode> route;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F7FF),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${route.length - 1} ${route.length == 2 ? 'segment' : 'segments'} to your destination',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < route.length; index++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  index == 0
                      ? Icons.my_location_rounded
                      : index == route.length - 1
                      ? Icons.flag_rounded
                      : Icons.circle,
                  size: index == 0 || index == route.length - 1 ? 17 : 9,
                  color: index == route.length - 1
                      ? const Color(0xFFE92332)
                      : const Color(0xFF3B82F6),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    index == 0
                        ? 'Start at ${route[index].label}'
                        : index == route.length - 1
                        ? 'Arrive at ${route[index].label}'
                        : 'Continue to ${route[index].label}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _NavigationInstructions extends StatelessWidget {
  const _NavigationInstructions({
    required this.destination,
    this.hasArrived = false,
    required this.isNavigating,
    required this.isStarting,
    this.status,
    this.outsideMall = false,
  });

  final String destination;
  final bool hasArrived;
  final bool isNavigating;
  final bool isStarting;
  final String? status;
  final bool outsideMall;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: hasArrived
            ? const Color(0xFFEAF6EF)
            : outsideMall
            ? const Color(0xFFFFF2E8)
            : const Color(0xFFF3F7FF),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(
            hasArrived
                ? Icons.check_circle_outline
                : outsideMall
                ? Icons.location_off_outlined
                : Icons.my_location_rounded,
            color: hasArrived
                ? const Color(0xFF16885B)
                : outsideMall
                ? const Color(0xFFE47721)
                : const Color(0xFF126BEB),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasArrived
                      ? "You've arrived!"
                      : isStarting
                      ? 'Checking your location'
                      : outsideMall
                      ? 'Outside the mall area'
                      : isNavigating
                      ? 'Following your live location'
                      : 'Location status',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  status ??
                      (hasArrived
                          ? 'You are near $destination.'
                          : 'Waiting for location updates.'),
                  style: const TextStyle(
                    color: Color(0xFF68727A),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Indoor GPS may be inaccurate. The blue dot only moves when your device reports a new location.',
                  style: TextStyle(color: Color(0xFF68727A), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
