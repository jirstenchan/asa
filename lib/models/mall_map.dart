enum MapNodeType { place, elevator, escalator, stairs }

class MapNode {
  const MapNode({
    required this.id,
    required this.label,
    required this.x,
    required this.y,
    this.type = MapNodeType.place,
  });

  final String id;
  final String label;
  final double x;
  final double y;
  final MapNodeType type;

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'x': x,
    'y': y,
    'type': type.name,
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
  );
}

class MapConnection {
  const MapConnection({required this.from, required this.to});

  final String from;
  final String to;

  Map<String, String> toJson() => {'from': from, 'to': to};

  factory MapConnection.fromJson(Map<String, dynamic> json) => MapConnection(
    from: json['from'] as String,
    to: json['to'] as String,
  );
}

class MallMap {
  const MallMap({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.nodes,
    required this.connections,
    required this.createdAt,
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
  final double? latitude;
  final double? longitude;
  final double? radiusMeters;
  final List<MapCalibrationPoint> calibrationPoints;

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'imagePath': imagePath,
    'nodes': nodes.map((node) => node.toJson()).toList(),
    'connections': connections.map((edge) => edge.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
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
  });

  final double x;
  final double y;
  final double latitude;
  final double longitude;

  Map<String, double> toJson() => {
    'x': x,
    'y': y,
    'latitude': latitude,
    'longitude': longitude,
  };

  factory MapCalibrationPoint.fromJson(Map<String, dynamic> json) =>
      MapCalibrationPoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );
}
