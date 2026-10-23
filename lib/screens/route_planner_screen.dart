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
    this.floors = const [],
    this.latitude,
    this.longitude,
    this.radiusMeters,
    this.calibrationPoints = const [],
    this.locationProvider,
  });

  final String mallName;
  final String? imagePath;
  final List<MapFloor> floors;
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
  Position? _position;
  Position? _previousMovementPosition;
  Offset? _liveMapLocation;
  String? _liveMapFloorId;
  String? _previewingFloorId;
  String? _locationStatus;
  String? _selectedFloorId;

  List<MapFloor> get _effectiveFloors => widget.floors.isNotEmpty
      ? widget.floors
      : [
          MapFloor(
            id: 'ground',
            name: 'Floor 1',
            imagePath: widget.imagePath ?? '',
          ),
        ];

  MapFloor get _activeFloor => _effectiveFloors.firstWhere(
    (floor) => floor.id == _selectedFloorId,
    orElse: () => _effectiveFloors.first,
  );

  List<MapCalibrationPoint> _calibrationForFloor(String floorId) {
    final configured = widget.calibrationPoints
        .where((point) => point.floorId == floorId)
        .toList(growable: false);
    if (hasUsableLocationCalibration(configured)) return configured;

    final latitude = widget.latitude;
    final longitude = widget.longitude;
    final radius = widget.radiusMeters;
    if (latitude == null ||
        longitude == null ||
        radius == null ||
        radius <= 0) {
      return const [];
    }

    // Use the mall geofence as a rough scale when the floor has no dimensions.
    return [
      MapCalibrationPoint(
        x: .5,
        y: .5,
        latitude: latitude,
        longitude: longitude,
        floorId: floorId,
        floorWidthMeters: radius * 2,
        floorHeightMeters: radius * 2,
        bearingDegrees: 0,
      ),
    ];
  }

  List<MapConnection> _connectionsForRoute(List<MapNode>? route) {
    if (route == null || route.length < 2) return const [];
    final routeEdges = <String>{};
    for (var index = 0; index < route.length - 1; index++) {
      final from = route[index].id;
      final to = route[index + 1].id;
      routeEdges.add('$from\u0000$to');
      routeEdges.add('$to\u0000$from');
    }
    return widget.connections
        .where((edge) => routeEdges.contains('${edge.from}\u0000${edge.to}'))
        .toList(growable: false);
  }

  List<MapNode> _nodesForRoute(List<MapNode>? route) {
    if (route == null) return widget.nodes;
    final routeNodeIds = route.map((node) => node.id).toSet();
    return widget.nodes
        .where((node) => routeNodeIds.contains(node.id))
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _selectedFloorId = _effectiveFloors.first.id;
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
    _previousMovementPosition = null;
    _liveMapLocation = null;
    _liveMapFloorId = null;
    _previewingFloorId = null;
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
      _selectedFloorId = route.first.floorId;
      _isNavigating = false;
      _hasArrived = false;
      _previousMovementPosition = null;
      _liveMapLocation = null;
      _liveMapFloorId = null;
      _previewingFloorId = null;
    });
  }

  Future<void> _startNavigation() async {
    if (_route == null) return;
    if (!hasUsableLocationCalibration(
      _calibrationForFloor(_route!.first.floorId),
    )) {
      _showMessage('Set a floor scale or mall radius before navigating.');
      return;
    }
    setState(() {
      _isStarting = true;
      _locationStatus = 'Checking movement tracking…';
    });
    try {
      await _locationProvider.ensurePermission();
      final position = await _locationProvider.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _isNavigating = true;
        _previousMovementPosition = position;
        _liveMapLocation = Offset(_route!.first.x, _route!.first.y);
        _liveMapFloorId = _route!.first.floorId;
        _previewingFloorId = null;
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

  void _updateLocation(Position position) {
    if (!mounted) return;
    final location = _advanceLiveMapLocation(position);
    setState(() {
      _position = position;
      _locationStatus = location == null
          ? 'Movement tracking needs a valid floor scale.'
          : 'Blue dot starts at your selected point and follows your movement.';
    });

    final destination = _route?.last;
    final liveLocation = _liveMapLocation;
    if (destination != null &&
        liveLocation != null &&
        destination.floorId == _liveMapFloorId) {
      final distance = mapDistanceMeters(
        from: liveLocation,
        to: Offset(destination.x, destination.y),
        calibrationPoints: _calibrationForFloor(destination.floorId),
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

  Offset? _advanceLiveMapLocation(Position position) {
    final previous = _previousMovementPosition;
    var nextLocation = _liveMapLocation;
    if (previous != null && nextLocation != null) {
      final floorId = _liveMapFloorId;
      if (floorId != null) {
        final update = estimateRelativeMovement(
          previous: previous,
          current: position,
          calibrationPoints: _calibrationForFloor(floorId),
        );
        final movement = update.mapOffset;
        if (movement != null) {
          nextLocation = Offset(
            nextLocation.dx + movement.dx,
            nextLocation.dy + movement.dy,
          );
        }
        if (update.shouldAdvanceBaseline) {
          _previousMovementPosition = position;
        }
      }
    } else {
      _previousMovementPosition = position;
    }
    _liveMapLocation = nextLocation;
    return _liveMapFloorId == _activeFloor.id &&
            _previewingFloorId != _activeFloor.id
        ? nextLocation
        : null;
  }

  Future<void> _selectFloor(String floorId) async {
    if (floorId == _selectedFloorId && _previewingFloorId != floorId) return;
    if (!_isNavigating || floorId == _liveMapFloorId) {
      setState(() {
        _selectedFloorId = floorId;
        if (floorId == _liveMapFloorId) _previewingFloorId = null;
      });
      return;
    }

    final floorName = _effectiveFloors
        .firstWhere((floor) => floor.id == floorId)
        .name;
    final didChangeFloors = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switching floors?'),
        content: Text(
          'Are you physically on $floorName, or are you just previewing its map?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Just previewing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('I changed floors'),
          ),
        ],
      ),
    );
    if (!mounted || didChangeFloors == null) return;

    if (!didChangeFloors) {
      setState(() {
        _selectedFloorId = floorId;
        _previewingFloorId = floorId;
      });
      return;
    }

    MapNode? transferPoint;
    for (final node in _route ?? const <MapNode>[]) {
      if (node.floorId == floorId) {
        transferPoint = node;
        break;
      }
    }
    if (transferPoint == null) {
      _showMessage('The planned route has no transfer point on this floor.');
      setState(() {
        _selectedFloorId = floorId;
        _previewingFloorId = floorId;
      });
      return;
    }

    setState(() {
      _selectedFloorId = floorId;
      _liveMapFloorId = floorId;
      _previewingFloorId = null;
      _previousMovementPosition = _position;
      _liveMapLocation = Offset(transferPoint!.x, transferPoint.y);
      _locationStatus = 'Location transferred to $floorName.';
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openFullScreen() {
    final route = _isNavigating || _hasArrived ? _route : null;
    final projectedLocation =
        _liveMapFloorId == _activeFloor.id &&
            _previewingFloorId != _activeFloor.id
        ? _liveMapLocation
        : null;
    final location = projectedLocation == null
        ? null
        : clampLocationToMap(projectedLocation);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullScreenMapScreen(
          imagePath: _activeFloor.imagePath.isEmpty
              ? null
              : _activeFloor.imagePath,
          nodes: _nodesForRoute(route),
          floorId: _activeFloor.id,
          connections: _connectionsForRoute(route),
          calibrationPoints: _calibrationForFloor(_activeFloor.id),
          routeNodeIds: route?.map((node) => node.id).toList(),
          destinationNodeId: _destinationId,
          deviceLocation: location,
          trackLiveLocation: _isNavigating,
          locationProvider: _locationProvider,
          initialPosition: _position,
          initialMapLocation: location,
          compactMarkers: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final showRoute = _isNavigating || _hasArrived;
    final routeIds = showRoute ? route?.map((node) => node.id).toList() : null;
    final projectedLocation =
        _liveMapFloorId == _activeFloor.id &&
            _previewingFloorId != _activeFloor.id
        ? _liveMapLocation
        : null;
    final visibleLocation = projectedLocation == null
        ? null
        : clampLocationToMap(projectedLocation);
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
              floors: _effectiveFloors,
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
              floors: _effectiveFloors,
              onChanged: (id) {
                setState(() {
                  _destinationId = id;
                  _clearRoute();
                });
              },
            ),
            const SizedBox(height: 16),
            if (_effectiveFloors.length > 1) ...[
              const SizedBox(height: 2),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final floor in _effectiveFloors)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(floor.name),
                          selected: floor.id == _selectedFloorId,
                          onSelected: (_) => _selectFloor(floor.id),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            MapPreview(
              height: 340,
              key: ValueKey(_activeFloor.id),
              imagePath: _activeFloor.imagePath.isEmpty
                  ? null
                  : _activeFloor.imagePath,
              nodes: _nodesForRoute(showRoute ? route : null),
              floorId: _activeFloor.id,
              connections: showRoute ? _connectionsForRoute(route) : const [],
              routeNodeIds: routeIds,
              currentNodeId: _isNavigating || _hasArrived ? null : _originId,
              destinationNodeId: _destinationId,
              deviceLocation: visibleLocation,
              emptyLabel: '',
              showControls: true,
              onFullScreenTap: _openFullScreen,
              compactMarkers: true,
            ),
            const SizedBox(height: 14),
            if (route == null)
              _RouteTip(nodeCount: widget.nodes.length)
            else if (_isNavigating || _hasArrived || _locationStatus != null)
              _NavigationInstructions(
                destination: route.last.label.isEmpty
                    ? route.last.type.displayName.toLowerCase()
                    : route.last.label,
                hasArrived: _hasArrived,
                isNavigating: _isNavigating,
                isStarting: _isStarting,
                status: _locationStatus,
              )
            else
              _RouteSummary(route: route, floors: _effectiveFloors),
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
    required this.floors,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final IconData icon;
  final String? value;
  final List<MapNode> nodes;
  final List<MapFloor> floors;
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
      Autocomplete<MapNode>(
        key: ValueKey('$label:$value'),
        initialValue: TextEditingValue(
          text: _selectedNodeLabel(nodes, floors, value),
        ),
        displayStringForOption: (node) => _routePlaceLabel(node, floors),
        optionsBuilder: (textEditingValue) {
          final query = textEditingValue.text.trim().toLowerCase();
          if (query.isEmpty) return nodes;
          return nodes.where((node) {
            final floor = floors.firstWhere(
              (item) => item.id == node.floorId,
              orElse: () =>
                  MapFloor(id: node.floorId, name: 'Floor', imagePath: ''),
            );
            final searchableText =
                '${_routePlaceLabel(node, floors)} ${node.type.displayName} '
                        '${node.customTypeName ?? ''} ${floor.name}'
                    .toLowerCase();
            return searchableText.contains(query);
          });
        },
        onSelected: (node) => onChanged(node.id),
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) =>
            TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: nodes.isNotEmpty,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onFieldSubmitted(),
              decoration: InputDecoration(
                hintText: nodes.isEmpty ? 'No spots available' : hint,
                prefixIcon: Icon(icon, size: 20),
                suffixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 11,
                ),
              ),
            ),
        optionsViewBuilder: (context, onSelected, options) {
          final matches = options.toList(growable: false);
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 5,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width - 36,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final node = matches[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(_routePlaceIcon(node.type), size: 20),
                        title: Text(
                          _routePlaceLabel(node, floors),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => onSelected(node),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ],
  );
}

String _selectedNodeLabel(
  List<MapNode> nodes,
  List<MapFloor> floors,
  String? nodeId,
) {
  for (final node in nodes) {
    if (node.id == nodeId) return _routePlaceLabel(node, floors);
  }
  return '';
}

String _routePlaceLabel(MapNode node, List<MapFloor> floors) {
  final name = node.label.isEmpty ? node.type.displayName : node.label;
  if (floors.length == 1) return name;
  final floor = floors.firstWhere(
    (item) => item.id == node.floorId,
    orElse: () => MapFloor(id: node.floorId, name: 'Floor', imagePath: ''),
  );
  return '$name · ${floor.name}';
}

IconData _routePlaceIcon(MapNodeType type) => switch (type) {
  MapNodeType.pathway => Icons.route_rounded,
  MapNodeType.store => Icons.storefront_outlined,
  MapNodeType.restroom => Icons.wc_rounded,
  MapNodeType.elevator => Icons.elevator_rounded,
  MapNodeType.escalator => Icons.escalator_rounded,
  MapNodeType.stairs => Icons.stairs_rounded,
  MapNodeType.custom => Icons.tune_rounded,
  MapNodeType.place => Icons.place_outlined,
};

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
  const _RouteSummary({required this.route, required this.floors});

  final List<MapNode> route;
  final List<MapFloor> floors;

  String _stepLabel(int index) {
    final node = route[index];
    if (index == 0) return 'Start at ${_routeNodeName(node)}';
    if (index == route.length - 1) return 'Arrive at ${_routeNodeName(node)}';
    final previous = route[index - 1];
    if (previous.floorId != node.floorId) {
      final floor = floors.firstWhere(
        (item) => item.id == node.floorId,
        orElse: () =>
            MapFloor(id: node.floorId, name: 'another floor', imagePath: ''),
      );
      final transport = switch (node.type) {
        MapNodeType.elevator => 'elevator',
        MapNodeType.escalator => 'escalator',
        MapNodeType.stairs => 'stairs',
        _ => 'connector',
      };
      return 'Take the $transport to ${floor.name}';
    }
    return 'Continue to ${_routeNodeName(node)}';
  }

  String _routeNodeName(MapNode node) =>
      node.label.isEmpty ? node.type.displayName.toLowerCase() : node.label;

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
                    _stepLabel(index),
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
  });

  final String destination;
  final bool hasArrived;
  final bool isNavigating;
  final bool isStarting;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: hasArrived ? const Color(0xFFEAF6EF) : const Color(0xFFF3F7FF),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(
            hasArrived ? Icons.check_circle_outline : Icons.my_location_rounded,
            color: hasArrived
                ? const Color(0xFF16885B)
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
                      : isNavigating
                      ? 'Following your movement'
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
                  'The blue dot starts at your selected point and moves from your device’s speed and direction.',
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
