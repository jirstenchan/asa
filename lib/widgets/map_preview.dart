import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import '../models/mall_map.dart';
import '../services/geo_location.dart';

class MapPreview extends StatefulWidget {
  const MapPreview({
    super.key,
    required this.height,
    this.imagePath,
    this.nodes = const [],
    this.floorId = 'ground',
    this.connections = const [],
    this.calibrationPoints = const [],
    this.routeNodeIds,
    this.currentNodeId,
    this.destinationNodeId,
    this.selectedNodeId,
    this.deviceLocation,
    this.onCanvasTap,
    this.onNodeTap,
    this.emptyLabel = 'Add a floor plan to preview this map',
    this.showControls = false,
    this.maxScale = 6,
    this.fillImageWidth = false,
    this.compactMarkers = false,
    this.allowFullScreen = true,
    this.onFullScreenTap,
  });

  final double height;
  final String? imagePath;
  final List<MapNode> nodes;
  final String floorId;
  final List<MapConnection> connections;
  final List<MapCalibrationPoint> calibrationPoints;
  final List<String>? routeNodeIds;
  final String? currentNodeId;
  final String? destinationNodeId;
  final String? selectedNodeId;
  final Offset? deviceLocation;
  final ValueChanged<Offset>? onCanvasTap;
  final ValueChanged<MapNode>? onNodeTap;
  final String emptyLabel;
  final bool showControls;
  final double maxScale;
  final bool fillImageWidth;
  final bool compactMarkers;
  final bool allowFullScreen;
  final VoidCallback? onFullScreenTap;

  @override
  State<MapPreview> createState() => _MapPreviewState();
}

class _MapPreviewState extends State<MapPreview> {
  final TransformationController _transformController =
      TransformationController();
  Size? _imageSize;
  Offset? _zoomFocus;
  StreamSubscription<CompassEvent>? _compassSubscription;
  double? _headingDegrees;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
    if (widget.deviceLocation != null) _listenForHeading();
  }

  @override
  void didUpdateWidget(covariant MapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _imageSize = null;
      _transformController.value = Matrix4.identity();
      _loadImageSize();
    }
    if (oldWidget.deviceLocation == null && widget.deviceLocation != null) {
      _listenForHeading();
    } else if (oldWidget.deviceLocation != null &&
        widget.deviceLocation == null) {
      unawaited(_compassSubscription?.cancel());
      _compassSubscription = null;
      _headingDegrees = null;
    }
  }

  void _listenForHeading() {
    _compassSubscription = FlutterCompass.events?.listen((event) {
      final heading = event.heading;
      if (!mounted || heading == null || !heading.isFinite) return;
      setState(() => _headingDegrees = heading);
    });
  }

  @override
  void dispose() {
    unawaited(_compassSubscription?.cancel());
    _transformController.dispose();
    super.dispose();
  }

  void _loadImageSize() {
    final path = widget.imagePath;
    if (path == null || path.isEmpty) return;
    final provider = FileImage(File(path));
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        if (mounted) {
          setState(() {
            _imageSize = Size(
              info.image.width.toDouble(),
              info.image.height.toDouble(),
            );
          });
        }
        stream.removeListener(listener);
      },
      onError: (Object error, StackTrace? stackTrace) {
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  void _zoomBy(double factor, Size size) {
    final currentZoom = _transformController.value.getMaxScaleOnAxis();
    final nextZoom = (currentZoom * factor)
        .clamp(1.0, widget.maxScale)
        .toDouble();
    if (nextZoom == currentZoom) return;
    final focus = _zoomFocus ?? Offset(size.width / 2, size.height / 2);
    final zoomFactor = nextZoom / currentZoom;
    _transformController.value = Matrix4.identity()
      ..translateByDouble(focus.dx, focus.dy, 0, 1)
      ..scaleByDouble(zoomFactor, zoomFactor, 1, 1)
      ..translateByDouble(-focus.dx, -focus.dy, 0, 1)
      ..multiply(_transformController.value);
  }

  void _openFullScreen() {
    final onFullScreenTap = widget.onFullScreenTap;
    if (onFullScreenTap != null) {
      onFullScreenTap();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullScreenMapScreen(
          imagePath: widget.imagePath,
          nodes: widget.nodes,
          floorId: widget.floorId,
          connections: widget.connections,
          calibrationPoints: widget.calibrationPoints,
          routeNodeIds: widget.routeNodeIds,
          currentNodeId: widget.currentNodeId,
          destinationNodeId: widget.destinationNodeId,
          deviceLocation: widget.deviceLocation,
          compactMarkers: widget.compactMarkers,
          maxScale: widget.maxScale,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : widget.height;
        final size = Size(width, height);
        final imageRect = widget.fillImageWidth
            ? _widthFittedRect(size, _imageSize)
            : _containedRect(size, _imageSize);
        final visibleNodes = widget.nodes
            .where((node) => node.floorId == widget.floorId)
            .toList(growable: false);
        final canvas = SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fromRect(
                rect: imageRect,
                child: widget.imagePath == null || widget.imagePath!.isEmpty
                    ? ColoredBox(
                        color: const Color(0xFFE8ECEF),
                        child: Center(
                          child: Text(
                            widget.emptyLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF77818A),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      )
                    : Image.file(
                        File(widget.imagePath!),
                        fit: BoxFit.fill,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: const Color(0xFFE8ECEF),
                          child: Center(
                            child: Text(
                              widget.emptyLabel,
                              style: const TextStyle(
                                color: Color(0xFF77818A),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _MapPathPainter(
                      nodes: visibleNodes,
                      connections: widget.connections,
                      calibrationPoints: widget.calibrationPoints,
                      routeNodeIds: widget.routeNodeIds,
                      imageRect: imageRect,
                      deviceLocation: widget.deviceLocation,
                      currentNodeId: widget.currentNodeId,
                      destinationNodeId: widget.destinationNodeId,
                    ),
                  ),
                ),
              ),
              if (widget.onCanvasTap != null)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapUp: (details) {
                      final point = details.localPosition;
                      if (imageRect.contains(point)) {
                        widget.onCanvasTap!(
                          Offset(
                            (point.dx - imageRect.left) / imageRect.width,
                            (point.dy - imageRect.top) / imageRect.height,
                          ),
                        );
                      }
                    },
                  ),
                ),
              if (!widget.compactMarkers)
                for (final node in visibleNodes)
                  Positioned(
                    left:
                        imageRect.left +
                        node.x * imageRect.width -
                        (widget.compactMarkers ? 33 : 23),
                    top:
                        imageRect.top +
                        node.y * imageRect.height -
                        (widget.compactMarkers ? 23 : 30),
                    child: GestureDetector(
                      onTap: widget.onNodeTap == null
                          ? null
                          : () => widget.onNodeTap!(node),
                      child: _NodeMarker(
                        node: node,
                        selected: node.id == widget.selectedNodeId,
                        isCurrent: node.id == widget.currentNodeId,
                        isDestination: node.id == widget.destinationNodeId,
                        compact: widget.compactMarkers,
                      ),
                    ),
                  ),
            ],
          ),
        );

        return SizedBox.fromSize(
          size: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Listener(
                  onPointerDown: (event) {
                    final renderObject = context.findRenderObject();
                    if (renderObject is RenderBox) {
                      _zoomFocus = renderObject.globalToLocal(event.position);
                    }
                  },
                  onPointerMove: (event) {
                    final renderObject = context.findRenderObject();
                    if (renderObject is RenderBox) {
                      _zoomFocus = renderObject.globalToLocal(event.position);
                    }
                  },
                  child: InteractiveViewer(
                    transformationController: _transformController,
                    constrained: true,
                    minScale: 1,
                    maxScale: widget.maxScale,
                    child: canvas,
                  ),
                ),
                if (widget.compactMarkers)
                  AnimatedBuilder(
                    animation: _transformController,
                    builder: (context, _) {
                      final matrix = _transformController.value;
                      return Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          for (final node in visibleNodes)
                            Builder(
                              builder: (context) {
                                final mapPoint = Offset(
                                  imageRect.left + node.x * imageRect.width,
                                  imageRect.top + node.y * imageRect.height,
                                );
                                final screenPoint = Offset(
                                  matrix[0] * mapPoint.dx + matrix[12],
                                  matrix[5] * mapPoint.dy + matrix[13],
                                );
                                return Positioned(
                                  left: screenPoint.dx - 27,
                                  top: screenPoint.dy - 9,
                                  child: GestureDetector(
                                    onTap: widget.onNodeTap == null
                                        ? null
                                        : () => widget.onNodeTap!(node),
                                    child: _NodeMarker(
                                      node: node,
                                      selected:
                                          node.id == widget.selectedNodeId,
                                      isCurrent:
                                          node.id == widget.currentNodeId,
                                      isDestination:
                                          node.id == widget.destinationNodeId,
                                      compact: true,
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                if (widget.deviceLocation != null)
                  AnimatedBuilder(
                    animation: _transformController,
                    builder: (context, _) {
                      final matrix = _transformController.value;
                      final mapPoint = Offset(
                        imageRect.left +
                            widget.deviceLocation!.dx * imageRect.width,
                        imageRect.top +
                            widget.deviceLocation!.dy * imageRect.height,
                      );
                      final screenPoint = Offset(
                        matrix[0] * mapPoint.dx + matrix[12],
                        matrix[5] * mapPoint.dy + matrix[13],
                      );
                      return Positioned(
                        left: screenPoint.dx - 19,
                        top: screenPoint.dy - 19,
                        child: IgnorePointer(
                          child: SizedBox(
                            width: 38,
                            height: 38,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (_headingDegrees != null)
                                  Transform.rotate(
                                    angle:
                                        (_headingDegrees! + 90) * math.pi / 180,
                                    child: CustomPaint(
                                      size: const Size(38, 38),
                                      painter: _HeadingConePainter(),
                                    ),
                                  ),
                                Container(
                                  width: 13,
                                  height: 13,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1677F8),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x663078FF),
                                        blurRadius: 3,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                if (widget.showControls)
                  Positioned(
                    right: 9,
                    top: 9,
                    child: Column(
                      children: [
                        _MapControl(
                          tooltip: 'Zoom in',
                          icon: Icons.add,
                          onPressed: () => _zoomBy(1.25, size),
                        ),
                        const SizedBox(height: 6),
                        _MapControl(
                          tooltip: 'Zoom out',
                          icon: Icons.remove,
                          onPressed: () => _zoomBy(0.8, size),
                        ),
                        if (widget.allowFullScreen) ...[
                          const SizedBox(height: 6),
                          _MapControl(
                            tooltip: 'View full screen',
                            icon: Icons.fullscreen,
                            onPressed: _openFullScreen,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class FullScreenMapScreen extends StatefulWidget {
  const FullScreenMapScreen({
    super.key,
    this.imagePath,
    this.nodes = const [],
    this.floorId = 'ground',
    this.connections = const [],
    this.calibrationPoints = const [],
    this.routeNodeIds,
    this.currentNodeId,
    this.destinationNodeId,
    this.deviceLocation,
    this.trackLiveLocation = false,
    this.locationProvider,
    this.initialPosition,
    this.initialMapLocation,
    this.compactMarkers = false,
    this.maxScale = 6,
  });

  final String? imagePath;
  final List<MapNode> nodes;
  final String floorId;
  final List<MapConnection> connections;
  final List<MapCalibrationPoint> calibrationPoints;
  final List<String>? routeNodeIds;
  final String? currentNodeId;
  final String? destinationNodeId;
  final Offset? deviceLocation;
  final bool trackLiveLocation;
  final LocationProvider? locationProvider;
  final Position? initialPosition;
  final Offset? initialMapLocation;
  final bool compactMarkers;
  final double maxScale;

  @override
  State<FullScreenMapScreen> createState() => _FullScreenMapScreenState();
}

class _FullScreenMapScreenState extends State<FullScreenMapScreen> {
  StreamSubscription<Position>? _subscription;
  Offset? _deviceLocation;
  Position? _previousPosition;

  @override
  void initState() {
    super.initState();
    _deviceLocation = widget.initialMapLocation ?? widget.deviceLocation;
    _previousPosition = widget.initialPosition;
    if (widget.trackLiveLocation && widget.locationProvider != null) {
      _subscription = widget.locationProvider!.watchPosition().listen(
        _updatePosition,
        onError: (Object error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Live location updates stopped: $error')),
            );
          }
        },
      );
    }
  }

  void _updatePosition(Position position) {
    final previous = _previousPosition;
    var nextLocation = _deviceLocation;
    if (previous != null && nextLocation != null) {
      final update = estimateRelativeMovement(
        previous: previous,
        current: position,
        calibrationPoints: widget.calibrationPoints,
      );
      final movement = update.mapOffset;
      if (movement != null) {
        nextLocation = clampLocationToMap(
          Offset(nextLocation.dx + movement.dx, nextLocation.dy + movement.dy),
        );
      }
      if (update.shouldAdvanceBaseline) {
        _previousPosition = position;
      }
    } else {
      _previousPosition = position;
    }
    if (!mounted) return;
    setState(() {
      _deviceLocation = nextLocation;
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Go back',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
      ),
      title: const Text('Map'),
      centerTitle: true,
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) => MapPreview(
            height: constraints.maxHeight,
            imagePath: widget.imagePath,
            nodes: widget.nodes,
            floorId: widget.floorId,
            connections: widget.connections,
            calibrationPoints: widget.calibrationPoints,
            routeNodeIds: widget.routeNodeIds,
            currentNodeId: widget.currentNodeId,
            destinationNodeId: widget.destinationNodeId,
            deviceLocation: _deviceLocation,
            showControls: true,
            allowFullScreen: false,
            compactMarkers: widget.compactMarkers,
            maxScale: widget.maxScale,
          ),
        ),
      ),
    ),
  );
}

class _MapControl extends StatelessWidget {
  const _MapControl({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .94),
    shape: const CircleBorder(),
    elevation: 2,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    ),
  );
}

class _NodeMarker extends StatelessWidget {
  const _NodeMarker({
    required this.node,
    required this.selected,
    required this.isCurrent,
    required this.isDestination,
    required this.compact,
  });

  final MapNode node;
  final bool selected;
  final bool isCurrent;
  final bool isDestination;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final markerLabel = node.type == MapNodeType.custom
        ? '${node.customTypeName}: ${node.label}'
        : node.label;
    final icon = switch (node.type) {
      MapNodeType.pathway => Icons.route_rounded,
      MapNodeType.store => Icons.storefront_rounded,
      MapNodeType.restroom => Icons.wc_rounded,
      MapNodeType.elevator => Icons.elevator_rounded,
      MapNodeType.escalator => Icons.escalator_rounded,
      MapNodeType.stairs => Icons.stairs_rounded,
      MapNodeType.custom => Icons.tune_rounded,
      MapNodeType.place => Icons.place_rounded,
    };
    final color = isCurrent
        ? const Color(0xFF1477F8)
        : isDestination
        ? const Color(0xFFE92332)
        : selected
        ? const Color(0xFFFF9D21)
        : const Color(0xFF20272E);

    return SizedBox(
      width: compact ? 54 : 88,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 18 : 32,
            height: compact ? 18 : 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: compact ? 10 : 18),
          ),
          if (markerLabel.isNotEmpty)
            Container(
              constraints: BoxConstraints(maxWidth: compact ? 54 : 88),
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                markerLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 7 : 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeadingConePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final cone = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx - 7, center.dy - 16)
      ..quadraticBezierTo(
        center.dx,
        center.dy - 20,
        center.dx + 7,
        center.dy - 16,
      )
      ..close();
    canvas.drawPath(cone, Paint()..color = const Color(0x553078FF));
  }

  @override
  bool shouldRepaint(covariant _HeadingConePainter oldDelegate) => false;
}

class _MapPathPainter extends CustomPainter {
  const _MapPathPainter({
    required this.nodes,
    required this.connections,
    required this.calibrationPoints,
    required this.routeNodeIds,
    required this.imageRect,
    required this.deviceLocation,
    required this.currentNodeId,
    required this.destinationNodeId,
  });

  final List<MapNode> nodes;
  final List<MapConnection> connections;
  final List<MapCalibrationPoint> calibrationPoints;
  final List<String>? routeNodeIds;
  final Rect imageRect;
  final Offset? deviceLocation;
  final String? currentNodeId;
  final String? destinationNodeId;

  Offset _point(MapNode node) => Offset(
    imageRect.left + node.x * imageRect.width,
    imageRect.top + node.y * imageRect.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final byId = {for (final node in nodes) node.id: node};
    for (final connection in connections) {
      final from = byId[connection.from];
      final to = byId[connection.to];
      if (from == null || to == null) continue;
      canvas.drawLine(
        _point(from),
        _point(to),
        Paint()
          ..color = const Color(0xAAFFFFFF)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        _point(from),
        _point(to),
        Paint()
          ..color = const Color(0xFF7E8992)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var index = 0; index < calibrationPoints.length; index++) {
      final point = calibrationPoints[index];
      final center = Offset(
        imageRect.left + point.x * imageRect.width,
        imageRect.top + point.y * imageRect.height,
      );
      canvas.drawCircle(center, 11, Paint()..color = const Color(0xFF16885B));
      final label = TextPainter(
        text: TextSpan(
          text: '${index + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(center.dx - label.width / 2, center.dy - label.height / 2),
      );
    }

    final ids = routeNodeIds;
    final route = ids
        ?.map((id) => byId[id])
        .whereType<MapNode>()
        .toList(growable: false);
    if (route != null && route.length > 1) {
      final points = route.map(_point).toList();
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xF0FFFFFF)
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFE87521)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      for (var index = 0; index < points.length - 1; index++) {
        final start = points[index];
        final end = points[index + 1];
        final middle = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
        final arrow = Path()
          ..moveTo(
            middle.dx + 5 * math.cos(angle),
            middle.dy + 5 * math.sin(angle),
          )
          ..lineTo(
            middle.dx - 4 * math.cos(angle - .65),
            middle.dy - 4 * math.sin(angle - .65),
          )
          ..lineTo(
            middle.dx - 4 * math.cos(angle + .65),
            middle.dy - 4 * math.sin(angle + .65),
          )
          ..close();
        canvas.drawPath(arrow, Paint()..color = Colors.white);
      }
    }

    for (final id in [currentNodeId, destinationNodeId]) {
      final node = byId[id];
      if (node == null) continue;
      final point = _point(node);
      final color = id == currentNodeId
          ? const Color(0xFF1477F8)
          : const Color(0xFFE92332);
      canvas.drawCircle(
        point,
        20,
        Paint()..color = color.withValues(alpha: .14),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MapPathPainter oldDelegate) =>
      oldDelegate.nodes != nodes ||
      oldDelegate.connections != connections ||
      oldDelegate.calibrationPoints != calibrationPoints ||
      oldDelegate.routeNodeIds != routeNodeIds ||
      oldDelegate.imageRect != imageRect ||
      oldDelegate.deviceLocation != deviceLocation ||
      oldDelegate.currentNodeId != currentNodeId ||
      oldDelegate.destinationNodeId != destinationNodeId;
}

Rect _containedRect(Size viewport, Size? imageSize) {
  if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) {
    return Offset.zero & viewport;
  }
  final scale = math.min(
    viewport.width / imageSize.width,
    viewport.height / imageSize.height,
  );
  final width = imageSize.width * scale;
  final height = imageSize.height * scale;
  return Rect.fromLTWH(
    (viewport.width - width) / 2,
    (viewport.height - height) / 2,
    width,
    height,
  );
}

Rect _widthFittedRect(Size viewport, Size? imageSize) {
  if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) {
    return Offset.zero & viewport;
  }
  final height = viewport.width * imageSize.height / imageSize.width;
  return Rect.fromLTWH(
    0,
    (viewport.height - height) / 2,
    viewport.width,
    height,
  );
}
