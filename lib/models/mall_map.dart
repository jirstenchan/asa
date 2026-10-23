enum MapNodeType {
  pathway,
  store,
  restroom,
  escalator,
  elevator,
  stairs,
  custom,
  place,
}

extension MapNodeTypeDisplayName on MapNodeType {
  String get displayName => switch (this) {
    MapNodeType.pathway => 'Pathway',
    MapNodeType.store => 'Store',
    MapNodeType.restroom => 'Restroom',
    MapNodeType.escalator => 'Escalator',
    MapNodeType.elevator => 'Elevator',
    MapNodeType.stairs => 'Stairs',
    MapNodeType.custom => 'Custom spot',
    MapNodeType.place => 'Place',
  };
}

class MapFloor {
  const MapFloor({
    required this.id,
    required this.name,
    required this.imagePath,
  });

  final String id;
  final String name;
  final String imagePath;

  Map<String, String> toJson() => {
    'id': id,
    'name': name,
    'imagePath': imagePath,
  };

  factory MapFloor.fromJson(Map<String, dynamic> json) => MapFloor(
    id: json['id'] as String,
    name: json['name'] as String,
    imagePath: json['imagePath'] as String,
  );
}

class MapNode {
  const MapNode({
    required this.id,
    required this.label,
    required this.x,
    required this.y,
    this.type = MapNodeType.store,
    this.floorId = 'ground',
    this.customTypeName,
  });

  final String id;
  final String label;
  final double x;
  final double y;
  final MapNodeType type;
  final String floorId;
  final String? customTypeName;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'x': x,
    'y': y,
    'type': type.name,
    'floorId': floorId,
    'customTypeName': customTypeName,
  };

  factory MapNode.fromJson(Map<String, dynamic> json) => MapNode(
    id: json['id'] as String,
    label: json['label'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    type: MapNodeType.values.firstWhere(
      (type) => type.name == json['type'],
      orElse: () => MapNodeType.place,
    ),
    floorId: json['floorId'] as String? ?? 'ground',
    customTypeName: json['customTypeName'] as String?,
  );
}

class MapConnection {
  const MapConnection({required this.from, required this.to});

  final String from;
  final String to;

  Map<String, String> toJson() => {'from': from, 'to': to};

  factory MapConnection.fromJson(Map<String, dynamic> json) =>
      MapConnection(from: json['from'] as String, to: json['to'] as String);
}

class MallMap {
  const MallMap({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.nodes,
    required this.connections,
    required this.createdAt,
    this.floors = const [],
    this.latitude,
    this.longitude,
    this.radiusMeters,
    this.calibrationPoints = const [],
  });

  final String id;
  final String name;
  final String imagePath;
  final List<MapNode> nodes;
  final List<MapConnection> connections;
  final DateTime createdAt;
  final List<MapFloor> floors;
  final double? latitude;
  final double? longitude;
  final double? radiusMeters;
  final List<MapCalibrationPoint> calibrationPoints;

  List<MapFloor> get effectiveFloors => floors.isNotEmpty
      ? floors
      : [MapFloor(id: 'ground', name: 'Floor 1', imagePath: imagePath)];

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'imagePath': imagePath,
    'nodes': nodes.map((node) => node.toJson()).toList(),
    'connections': connections.map((edge) => edge.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'floors': floors.map((floor) => floor.toJson()).toList(),
    'latitude': ?latitude,
    'longitude': ?longitude,
    'radiusMeters': ?radiusMeters,
    'calibrationPoints': calibrationPoints
        .map((point) => point.toJson())
        .toList(),
  };

  factory MallMap.fromJson(Map<String, dynamic> json) => MallMap(
    id: json['id'] as String,
    name: json['name'] as String,
    imagePath: json['imagePath'] as String,
    nodes: (json['nodes'] as List<dynamic>)
        .map((node) => MapNode.fromJson(node as Map<String, dynamic>))
        .toList(),
    connections: (json['connections'] as List<dynamic>)
        .map((edge) => MapConnection.fromJson(edge as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    floors:
        (json['floors'] as List<dynamic>?)
            ?.map((floor) => MapFloor.fromJson(floor as Map<String, dynamic>))
            .toList() ??
        const [],
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    radiusMeters: (json['radiusMeters'] as num?)?.toDouble(),
    calibrationPoints:
        (json['calibrationPoints'] as List<dynamic>?)
            ?.map(
              (point) =>
                  MapCalibrationPoint.fromJson(point as Map<String, dynamic>),
            )
            .toList() ??
        const [],
  );
}

class MapCalibrationPoint {
  const MapCalibrationPoint({
    required this.x,
    required this.y,
    required this.latitude,
    required this.longitude,
    this.floorId = 'ground',
    this.floorWidthMeters,
    this.floorHeightMeters,
    this.bearingDegrees,
  });

  final double x;
  final double y;
  final double latitude;
  final double longitude;
  final String floorId;
  final double? floorWidthMeters;
  final double? floorHeightMeters;
  final double? bearingDegrees;

  Map<String, Object?> toJson() => {
    'x': x,
    'y': y,
    'latitude': latitude,
    'longitude': longitude,
    'floorId': floorId,
    'floorWidthMeters': ?floorWidthMeters,
    'floorHeightMeters': ?floorHeightMeters,
    'bearingDegrees': ?bearingDegrees,
  };

  factory MapCalibrationPoint.fromJson(Map<String, dynamic> json) =>
      MapCalibrationPoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        floorId: json['floorId'] as String? ?? 'ground',
        floorWidthMeters: (json['floorWidthMeters'] as num?)?.toDouble(),
        floorHeightMeters: (json['floorHeightMeters'] as num?)?.toDouble(),
        bearingDegrees: (json['bearingDegrees'] as num?)?.toDouble(),
      );
}
