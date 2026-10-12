import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/mall_map.dart';

class MapPreview extends StatefulWidget {
  const MapPreview({
    super.key,
    required this.height,
    this.imagePath,
    this.nodes = const [],
    this.connections = const [],
    this.calibrationPoints = const [],
    this.routeNodeIds,
    this.currentNodeId,
    this.destinationNodeId,
    this.selectedNodeId,
    this.trackerProgress,
    this.deviceLocation,
    this.onCanvasTap,
    this.onNodeTap,
    this.emptyLabel = 'Add a floor plan to preview this map',
    this.showControls = false,
  });

  final double height;
  final String? imagePath;
  final List<MapNode> nodes;
  final List<MapConnection> connections;
  final List<MapCalibrationPoint> calibrationPoints;
  final List<String>? routeNodeIds;
  final String? currentNodeId;
  final String? destinationNodeId;
  final String? selectedNodeId;
  final double? trackerProgress;
  final Offset? deviceLocation;
  final ValueChanged<Offset>? onCanvasTap;
  final ValueChanged<MapNode>? onNodeTap;
  final String emptyLabel;
  final bool showControls;

  @override
  State<MapPreview> createState() => _MapPreviewState();
}

class _MapPreviewState extends State<MapPreview> {
  final TransformationController _transformController =
      TransformationController();
  Size? _imageSize;
  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  @override
  void didUpdateWidget(covariant MapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _imageSize = null;
      _transformController.value = Matrix4.identity();
      _zoom = 1;
      _loadImageSize();
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _loadImageSize() {
    final path = widget.imagePath;
    if (path == null) return;
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
    final nextZoom = (_zoom * factor).clamp(1.0, 6.0).toDouble();
    final center = Offset(size.width / 2, size.height / 2);
    _transformController.value = Matrix4.identity()
      ..translateByDouble(
        -center.dx * (nextZoom - 1),
        -center.dy * (nextZoom - 1),
        0,
        1,
      )
      ..scaleByDouble(nextZoom, nextZoom, 1, 1);
    setState(() => _zoom = nextZoom);
  }

  void _openFullScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullScreenMapScreen(
          imagePath: widget.imagePath,
          nodes: widget.nodes,
          connections: widget.connections,
          calibrationPoints: widget.calibrationPoints,
          routeNodeIds: widget.routeNodeIds,
          currentNodeId: widget.currentNodeId,
          destinationNodeId: widget.destinationNodeId,
          trackerProgress: widget.trackerProgress,
          deviceLocation: widget.deviceLocation,
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
        final imageRect = _containedRect(size, _imageSize);
        final canvas = SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fromRect(
                rect: imageRect,
                child: widget.imagePath == null
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
                      nodes: widget.nodes,
                      connections: widget.connections,
                      calibrationPoints: widget.calibrationPoints,
                      routeNodeIds: widget.routeNodeIds,
                      imageRect: imageRect,
                      trackerProgress: widget.trackerProgress,
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
              for (final node in widget.nodes)
                Positioned(
                  left: imageRect.left + node.x * imageRect.width - 23,
                  top: imageRect.top + node.y * imageRect.height - 30,
                  child: GestureDetector(
                    onTap: widget.onNodeTap == null
                        ? null
                        : () => widget.onNodeTap!(node),
                    child: _NodeMarker(
                      node: node,
                      selected: node.id == widget.selectedNodeId,
                      isCurrent: node.id == widget.currentNodeId,
                      isDestination: node.id == widget.destinationNodeId,
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
                InteractiveViewer(
                  transformationController: _transformController,
                  constrained: true,
                  minScale: 1,
                  maxScale: 6,
                  child: canvas,
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
                        const SizedBox(height: 6),
                        _MapControl(
                          tooltip: 'View full screen',
                          icon: Icons.fullscreen,
                          onPressed: _openFullScreen,
                        ),
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

class FullScreenMapScreen extends StatelessWidget {
  const FullScreenMapScreen({
    super.key,
    this.imagePath,
    this.nodes = const [],
    this.connections = const [],
    this.calibrationPoints = const [],
    this.routeNodeIds,
    this.currentNodeId,
    this.destinationNodeId,
    this.trackerProgress,
    this.deviceLocation,
  });

  final String? imagePath;
  final List<MapNode> nodes;
  final List<MapConnection> connections;
  final List<MapCalibrationPoint> calibrationPoints;
  final List<String>? routeNodeIds;
  final String? currentNodeId;
  final String? destinationNodeId;
  final double? trackerProgress;
  final Offset? deviceLocation;

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
            imagePath: imagePath,
            nodes: nodes,
            connections: connections,
            calibrationPoints: calibrationPoints,
            routeNodeIds: routeNodeIds,
            currentNodeId: currentNodeId,
            destinationNodeId: destinationNodeId,
            trackerProgress: trackerProgress,
            deviceLocation: deviceLocation,
            showControls: true,
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
  });

  final MapNode node;
  final bool selected;
  final bool isCurrent;
  final bool isDestination;

  @override
  Widget build(BuildContext context) {
    final icon = switch (node.type) {
      MapNodeType.place => Icons.place_rounded,
      MapNodeType.elevator => Icons.elevator_rounded,
      MapNodeType.escalator => Icons.escalator_rounded,
      MapNodeType.stairs => Icons.stairs_rounded,
    };
    final color = isCurrent
        ? const Color(0xFF1477F8)
        : isDestination
        ? const Color(0xFFE92332)
        : selected
        ? const Color(0xFFFF9D21)
        : const Color(0xFF20272E);

    return SizedBox(
      width: 88,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
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
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          if (node.label.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxWidth: 88),
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                node.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapPathPainter extends CustomPainter {
  const _MapPathPainter({
    required this.nodes,
    required this.connections,
    required this.calibrationPoints,
    required this.routeNodeIds,
    required this.imageRect,
    required this.trackerProgress,
    required this.deviceLocation,
    required this.currentNodeId,
    required this.destinationNodeId,
  });

  final List<MapNode> nodes;
  final List<MapConnection> connections;
  final List<MapCalibrationPoint> calibrationPoints;
  final List<String>? routeNodeIds;
  final Rect imageRect;
  final double? trackerProgress;
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
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF0878FF)
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      for (var index = 0; index < points.length - 1; index++) {
        final start = points[index];
        final end = points[index + 1];
        final middle = Offset(
          (start.dx + end.dx) / 2,
          (start.dy + end.dy) / 2,
        );
        final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
        final arrow = Path()
          ..moveTo(middle.dx + 7 * math.cos(angle), middle.dy + 7 * math.sin(angle))
          ..lineTo(
            middle.dx - 6 * math.cos(angle - .65),
            middle.dy - 6 * math.sin(angle - .65),
          )
          ..lineTo(
            middle.dx - 6 * math.cos(angle + .65),
            middle.dy - 6 * math.sin(angle + .65),
          )
          ..close();
        canvas.drawPath(arrow, Paint()..color = Colors.white);
      }

      final progress = trackerProgress;
      if (progress != null && route.length > 1) {
        final scaled = progress.clamp(0.0, 1.0) * (points.length - 1);
        final segment = math.min(scaled.floor(), points.length - 2);
        final fraction = scaled - segment;
        final point = Offset.lerp(
          points[segment],
          points[segment + 1],
          fraction,
        )!;
        canvas.drawCircle(point, 12, Paint()..color = Colors.white);
        canvas.drawCircle(point, 8, Paint()..color = const Color(0xFF0878FF));
        canvas.drawCircle(
          point,
          14,
          Paint()
            ..color = const Color(0x550878FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    for (final id in [currentNodeId, destinationNodeId]) {
      final node = byId[id];
      if (node == null) continue;
      final point = _point(node);
      final color = id == currentNodeId
          ? const Color(0xFF1477F8)
          : const Color(0xFFE92332);
      canvas.drawCircle(point, 20, Paint()..color = color.withValues(alpha: .14));
    }

    final liveLocation = deviceLocation;
    if (liveLocation != null) {
      final point = Offset(
        imageRect.left + liveLocation.dx * imageRect.width,
        imageRect.top + liveLocation.dy * imageRect.height,
      );
      canvas.drawCircle(point, 15, Paint()..color = const Color(0x442A85FF));
      canvas.drawCircle(point, 8, Paint()..color = Colors.white);
      canvas.drawCircle(
        point,
        6,
        Paint()..color = const Color(0xFF1677F8),
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
      oldDelegate.trackerProgress != trackerProgress ||
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
