import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/mall_map.dart';
import '../services/map_store.dart';
import '../widgets/map_preview.dart';

class CreateMapScreen extends StatefulWidget {
  const CreateMapScreen({
    super.key,
    required this.store,
    this.initialMap,
    this.pickImagePath,
  });

  final MapStore store;
  final MallMap? initialMap;
  final Future<String?> Function()? pickImagePath;

  @override
  State<CreateMapScreen> createState() => _CreateMapScreenState();
}

enum _EditMode { addNode, connect }

class _CreateMapScreenState extends State<CreateMapScreen> {
  final _nameController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _radiusController = TextEditingController(text: '100');
  final _floorWidthController = TextEditingController();
  final _floorHeightController = TextEditingController();
  final _picker = ImagePicker();
  final List<MapFloor> _floors = [];
  final List<MapNode> _nodes = [];
  final List<MapConnection> _connections = [];
  final List<MapCalibrationPoint> _calibrationPoints = [];
  final Map<String, List<String>> _scaleInputsByFloor = {};
  String? _activeFloorId;
  String? _selectedNodeId;
  _EditMode _mode = _EditMode.addNode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final map = widget.initialMap;
    if (map == null) return;
    _nameController.text = map.name;
    _latitudeController.text = map.latitude?.toString() ?? '';
    _longitudeController.text = map.longitude?.toString() ?? '';
    _radiusController.text = map.radiusMeters?.toString() ?? '100';
    _floors.addAll(map.effectiveFloors);
    _nodes.addAll(map.nodes);
    _connections.addAll(map.connections);
    _calibrationPoints.addAll(map.calibrationPoints);
    _activeFloorId = _floors.first.id;
    _loadScaleForFloor(_floors.first.id);
  }

  MapFloor? get _activeFloor {
    for (final floor in _floors) {
      if (floor.id == _activeFloorId) return floor;
    }
    return null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    _floorWidthController.dispose();
    _floorHeightController.dispose();
    super.dispose();
  }

  void _loadScaleForFloor(String floorId) {
    final cached = _scaleInputsByFloor[floorId];
    if (cached != null) {
      _floorWidthController.text = cached[0];
      _floorHeightController.text = cached[1];
      return;
    }
    MapCalibrationPoint? point;
    for (final item in _calibrationPoints) {
      if (item.floorId == floorId) {
        point = item;
        break;
      }
    }
    _floorWidthController.text = point?.floorWidthMeters?.toString() ?? '';
    _floorHeightController.text = point?.floorHeightMeters?.toString() ?? '';
    _cacheScaleInputs(floorId);
  }

  void _cacheScaleInputs(String floorId) {
    _scaleInputsByFloor[floorId] = [
      _floorWidthController.text,
      _floorHeightController.text,
    ];
  }

  List<MapCalibrationPoint> _gpsCalibrationForMap({
    required double latitude,
    required double longitude,
  }) {
    final activeFloorId = _activeFloorId;
    if (activeFloorId != null) _cacheScaleInputs(activeFloorId);
    final result = <MapCalibrationPoint>[];
    for (final floor in _floors) {
      final values = _scaleInputsByFloor[floor.id];
      if (values == null) continue;
      final width = double.tryParse(values[0]);
      final height = double.tryParse(values[1]);
      if (width == null || width <= 0 || height == null || height <= 0) {
        continue;
      }
      result.add(
        MapCalibrationPoint(
          x: .5,
          y: .5,
          latitude: latitude,
          longitude: longitude,
          floorId: floor.id,
          floorWidthMeters: width,
          floorHeightMeters: height,
          bearingDegrees: 0,
        ),
      );
    }
    return result;
  }

  void _selectFloor(String floorId) {
    final currentFloorId = _activeFloorId;
    if (currentFloorId != null) _cacheScaleInputs(currentFloorId);
    setState(() {
      _activeFloorId = floorId;
      if (_mode != _EditMode.connect) _selectedNodeId = null;
    });
    _loadScaleForFloor(floorId);
  }

  Future<void> _chooseImage({MapFloor? floor}) async {
    try {
      final imagePath = await _pickImagePath();
      if (imagePath != null && mounted) {
        setState(() {
          if (floor == null) {
            final newFloor = MapFloor(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              name: 'Floor ${_floors.length + 1}',
              imagePath: imagePath,
            );
            _floors.add(newFloor);
            _activeFloorId = newFloor.id;
            _loadScaleForFloor(newFloor.id);
          } else {
            final index = _floors.indexWhere((item) => item.id == floor.id);
            if (index >= 0) {
              _floors[index] = MapFloor(
                id: floor.id,
                name: floor.name,
                imagePath: imagePath,
              );
            }
          }
        });
      }
    } catch (error) {
      if (mounted) _showMessage('Could not open your photos: $error');
    }
  }

  Future<String?> _pickImagePath() async {
    final pickImagePath = widget.pickImagePath;
    if (pickImagePath != null) return pickImagePath();
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    return image?.path;
  }

  Future<void> _uploadFloorImage() async {
    final floor = _activeFloor;
    await _chooseImage(floor: floor);
  }

  Future<void> _addFloor() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _FloorNameDialog(
        title: 'Add a floor',
        initialName: 'Floor ${_floors.length + 1}',
        actionLabel: 'Continue',
      ),
    );
    if (!mounted || name == null) return;
    if (name.trim().isEmpty) {
      _showMessage('Floor names cannot be empty.');
      return;
    }
    try {
      final imagePath = await _pickImagePath();
      if (imagePath == null || !mounted) return;
      setState(() {
        final floor = MapFloor(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name.trim(),
          imagePath: imagePath,
        );
        _floors.add(floor);
        _activeFloorId = floor.id;
        _loadScaleForFloor(floor.id);
      });
    } catch (error) {
      if (mounted) _showMessage('Could not open your photos: $error');
    }
  }

  Future<void> _renameFloor(MapFloor floor) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _FloorNameDialog(
        title: 'Rename floor',
        initialName: floor.name,
        actionLabel: 'Save',
      ),
    );
    if (!mounted || name == null) return;
    if (name.trim().isEmpty) {
      _showMessage('Floor names cannot be empty.');
      return;
    }
    setState(() {
      final index = _floors.indexWhere((item) => item.id == floor.id);
      if (index >= 0) {
        _floors[index] = MapFloor(
          id: floor.id,
          name: name.trim(),
          imagePath: floor.imagePath,
        );
      }
    });
  }

  void _removeFloor(MapFloor floor) {
    if (_floors.length == 1) {
      _showMessage('A map must have at least one floor.');
      return;
    }
    setState(() {
      _floors.removeWhere((item) => item.id == floor.id);
      _scaleInputsByFloor.remove(floor.id);
      final removedNodeIds = _nodes
          .where((node) => node.floorId == floor.id)
          .map((node) => node.id)
          .toSet();
      _nodes.removeWhere((node) => removedNodeIds.contains(node.id));
      _calibrationPoints.removeWhere((point) => point.floorId == floor.id);
      _connections.removeWhere(
        (edge) =>
            removedNodeIds.contains(edge.from) ||
            removedNodeIds.contains(edge.to),
      );
      _activeFloorId = _floors.first.id;
      _loadScaleForFloor(_activeFloorId!);
      if (removedNodeIds.contains(_selectedNodeId)) _selectedNodeId = null;
    });
  }

  Future<void> _addNode(Offset position) async {
    final floor = _activeFloor;
    if (floor == null) return;
    final details = await _askForNodeDetails(title: 'Label this spot');
    if (details == null || !mounted) return;
    final label = details.label?.trim() ?? '';
    if (label.isEmpty && !_allowsEmptyNodeName(details.type)) {
      _showMessage('Spot names cannot be empty.');
      return;
    }
    final customTypeName = details.customTypeName?.trim();
    if (details.type == MapNodeType.custom &&
        (customTypeName == null || customTypeName.isEmpty)) {
      _showMessage('Enter a name for this custom node type.');
      return;
    }
    setState(() {
      _nodes.add(
        MapNode(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          label: label,
          x: position.dx.clamp(.025, .975).toDouble(),
          y: position.dy.clamp(.035, .965).toDouble(),
          type: details.type,
          floorId: floor.id,
          customTypeName: customTypeName,
        ),
      );
    });
  }

  Future<void> _handleCanvasTap(Offset position) async {
    await _addNode(position);
  }

  Future<void> _handleNodeTap(MapNode node) async {
    if (_mode == _EditMode.connect) {
      if (_selectedNodeId == null) {
        setState(() => _selectedNodeId = node.id);
        _showMessage(
          'Now tap the next spot to connect to ${node.label.isEmpty ? node.type.displayName.toLowerCase() : node.label}.',
        );
        return;
      }
      if (_selectedNodeId == node.id) {
        setState(() => _selectedNodeId = null);
        return;
      }
      final firstNode = _nodes.firstWhere((item) => item.id == _selectedNodeId);
      if (firstNode.floorId != node.floorId &&
          (firstNode.type != node.type ||
              !{
                MapNodeType.elevator,
                MapNodeType.escalator,
                MapNodeType.stairs,
              }.contains(node.type))) {
        _showMessage(
          'Connect floors using matching elevator, escalator, or stairs nodes.',
        );
        return;
      }
      final firstNodeId = _selectedNodeId!;
      final alreadyConnected = _connections.any(
        (edge) =>
            (edge.from == firstNodeId && edge.to == node.id) ||
            (edge.to == firstNodeId && edge.from == node.id),
      );
      if (alreadyConnected) {
        setState(() {
          _connections.removeWhere(
            (edge) =>
                (edge.from == firstNodeId && edge.to == node.id) ||
                (edge.to == firstNodeId && edge.from == node.id),
          );
          _selectedNodeId = null;
        });
        _showMessage('Connection removed.');
      } else {
        setState(() {
          _connections.add(MapConnection(from: _selectedNodeId!, to: node.id));
          _selectedNodeId = null;
        });
        _showMessage('Connection added.');
      }
      return;
    }
    await _editNode(node);
  }

  Future<void> _editNode(MapNode node) async {
    final result = await showDialog<_NodeAction>(
      context: context,
      builder: (_) => _SpotLabelDialog(
        title: 'Edit map spot',
        initialLabel: node.label,
        initialType: node.type == MapNodeType.place
            ? MapNodeType.store
            : node.type,
        initialCustomTypeName: node.customTypeName,
        showDelete: true,
      ),
    );
    if (!mounted || result == null) return;
    if (result.isDelete) {
      setState(() {
        _nodes.removeWhere((item) => item.id == node.id);
        _connections.removeWhere(
          (edge) => edge.from == node.id || edge.to == node.id,
        );
        if (_selectedNodeId == node.id) _selectedNodeId = null;
      });
    } else if (result.label case final String label) {
      if (label.isEmpty && !_allowsEmptyNodeName(result.type)) {
        _showMessage('Spot names cannot be empty.');
        return;
      }
      final customTypeName = result.customTypeName?.trim();
      if (result.type == MapNodeType.custom &&
          (customTypeName == null || customTypeName.isEmpty)) {
        _showMessage('Enter a name for this custom node type.');
        return;
      }
      setState(() {
        final index = _nodes.indexWhere((item) => item.id == node.id);
        _nodes[index] = MapNode(
          id: node.id,
          label: label,
          x: node.x,
          y: node.y,
          type: result.type,
          floorId: node.floorId,
          customTypeName: customTypeName,
        );
      });
    }
  }

  Future<_NodeAction?> _askForNodeDetails({required String title}) async {
    final result = await showDialog<_NodeAction>(
      context: context,
      builder: (_) => _SpotLabelDialog(title: title, actionLabel: 'Add spot'),
    );
    return result;
  }

  Future<void> _saveMap() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Give your map a name before saving.');
      return;
    }
    if (_floors.isEmpty ||
        _floors.any((floor) => floor.imagePath.trim().isEmpty)) {
      _showMessage('Upload a map image before saving.');
      return;
    }
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    final radiusMeters = double.tryParse(_radiusController.text.trim());
    if (latitude == null || latitude < -90 || latitude > 90) {
      _showMessage('Enter a valid latitude between -90 and 90.');
      return;
    }
    if (longitude == null || longitude < -180 || longitude > 180) {
      _showMessage('Enter a valid longitude between -180 and 180.');
      return;
    }
    if (radiusMeters == null || radiusMeters <= 0) {
      _showMessage('Enter a mall radius greater than zero meters.');
      return;
    }
    setState(() => _saving = true);
    try {
      final map = await widget.store.saveMap(
        name: name,
        pickedImagePath: _floors.first.imagePath,
        existingMap: widget.initialMap,
        floors: _floors,
        nodes: _nodes,
        connections: _connections,
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusMeters,
        calibrationPoints: _gpsCalibrationForMap(
          latitude: latitude,
          longitude: longitude,
        ),
      );
      if (mounted) Navigator.pop(context, map);
    } catch (error) {
      if (mounted) _showMessage('Could not save your map: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Go back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
        ),
        title: Text(widget.initialMap == null ? 'Create map' : 'Edit map'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            const _StepHeading(number: '01', title: 'Name your map'),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'e.g. SM Seaside',
                prefixIcon: Icon(Icons.edit_location_alt_outlined),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Mall location & radius',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Used to tell whether you are inside the mall area.',
              style: TextStyle(color: Color(0xFF737B81), fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('mall-latitude'),
                    controller: _latitudeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Latitude'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('mall-longitude'),
                    controller: _longitudeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Longitude'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('mall-radius'),
              controller: _radiusController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Mall radius (meters)',
                prefixIcon: Icon(Icons.radar_rounded),
              ),
            ),
            const SizedBox(height: 26),
            _StepHeading(
              number: '02',
              title: 'Add a floor plan',
              trailing: TextButton.icon(
                onPressed: _floors.isEmpty
                    ? _chooseImage
                    : _activeFloor?.imagePath.isEmpty == true
                    ? _uploadFloorImage
                    : _addFloor,
                icon: Icon(
                  _floors.isEmpty || _activeFloor?.imagePath.isEmpty == true
                      ? Icons.file_upload_outlined
                      : Icons.add_rounded,
                  size: 18,
                ),
                label: Text(
                  _floors.isEmpty || _activeFloor?.imagePath.isEmpty == true
                      ? 'Upload image'
                      : 'Add floor',
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_floors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final floor in _floors)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InputChip(
                            label: Text(floor.name),
                            selected: floor.id == _activeFloorId,
                            onPressed: () => _selectFloor(floor.id),
                            onDeleted: _floors.length > 1
                                ? () => _removeFloor(floor)
                                : null,
                          ),
                        ),
                      TextButton.icon(
                        onPressed: _activeFloor == null
                            ? null
                            : _uploadFloorImage,
                        icon: const Icon(Icons.image_outlined, size: 17),
                        label: const Text('Change image'),
                      ),
                      TextButton.icon(
                        onPressed: _activeFloor == null
                            ? null
                            : () => _renameFloor(_activeFloor!),
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label: const Text('Rename'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_activeFloor == null)
              InkWell(
                onTap: _chooseImage,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  height: 210,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F4F5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE3E6E8)),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 34,
                        color: Color(0xFF7D858B),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Tap to choose a map image',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'JPG, PNG or other image formats',
                        style: TextStyle(
                          color: Color(0xFF858B90),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              MapPreview(
                height: 340,
                key: ValueKey(_activeFloor!.id),
                imagePath: _activeFloor!.imagePath,
                nodes: _nodes,
                floorId: _activeFloor!.id,
                connections: _connections,
                selectedNodeId: _selectedNodeId,
                onCanvasTap: _mode == _EditMode.addNode
                    ? _handleCanvasTap
                    : null,
                onNodeTap: _handleNodeTap,
                emptyLabel: '',
                showControls: true,
                compactMarkers: true,
                maxScale: 14,
              ),
            const SizedBox(height: 25),
            Row(
              children: [
                const Expanded(
                  child: _StepHeading(number: '03', title: 'Add spots & paths'),
                ),
                Text(
                  '${_nodes.length} spots',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF777F85),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('floor-width-meters'),
                    controller: _floorWidthController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _cacheScaleInputs(_activeFloor!.id),
                    decoration: const InputDecoration(
                      labelText: 'Floor width (m)',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('floor-height-meters'),
                    controller: _floorHeightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _cacheScaleInputs(_activeFloor!.id),
                    decoration: const InputDecoration(
                      labelText: 'Floor height (m)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            const Text(
              'Optional: enter the floor plan size for a better GPS scale. '
              'Without it, the mall radius estimates the map size.',
              style: TextStyle(color: Color(0xFF68727A), fontSize: 11),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ModeButton(
                    icon: Icons.add_location_alt_outlined,
                    label: 'Add spot',
                    isSelected: _mode == _EditMode.addNode,
                    onTap: () {
                      setState(() {
                        _mode = _EditMode.addNode;
                        _selectedNodeId = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ModeButton(
                    icon: Icons.route_outlined,
                    label: 'Connect spots',
                    isSelected: _mode == _EditMode.connect,
                    onTap: () {
                      setState(() {
                        _mode = _EditMode.connect;
                        _selectedNodeId = null;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F7F8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Color(0xFF68727A),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _activeFloor == null
                          ? 'Upload a floor plan first. Then tap the map to place labeled spots.'
                          : _mode == _EditMode.addNode
                          ? 'Tap anywhere on the floor plan to add a labeled spot. Tap a spot to rename or delete it.'
                          : _selectedNodeId == null
                          ? 'Tap two spots to connect them. Tap the same pair again to remove a connection. For floor changes, use matching elevator, escalator, or stairs spots.'
                          : 'Tap another spot to connect it, or switch floors and tap its matching elevator, escalator, or stairs spot.',
                      style: const TextStyle(
                        color: Color(0xFF68727A),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _saving ? null : _saveMap,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save map'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloorNameDialog extends StatefulWidget {
  const _FloorNameDialog({
    required this.title,
    required this.initialName,
    required this.actionLabel,
  });

  final String title;
  final String initialName;
  final String actionLabel;

  @override
  State<_FloorNameDialog> createState() => _FloorNameDialogState();
}

class _FloorNameDialogState extends State<_FloorNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const Key('floor-name'),
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(labelText: 'Floor name'),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
    ],
  );
}

class _StepHeading extends StatelessWidget {
  const _StepHeading({
    required this.number,
    required this.title,
    this.trailing,
  });

  final String number;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFFFFE8EA),
          shape: BoxShape.circle,
        ),
        child: Text(
          number,
          style: const TextStyle(
            color: Color(0xFFE92332),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      ?trailing,
    ],
  );
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 18),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 47),
      foregroundColor: isSelected ? Colors.white : const Color(0xFF25292D),
      backgroundColor: isSelected ? const Color(0xFF151719) : Colors.white,
      side: BorderSide(
        color: isSelected ? const Color(0xFF151719) : const Color(0xFFE2E5E7),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

class _NodeAction {
  const _NodeAction._({
    this.label,
    this.type = MapNodeType.store,
    this.customTypeName,
    this.isDelete = false,
  });

  const _NodeAction.rename(
    String label,
    MapNodeType type, [
    String? customTypeName,
  ]) : this._(label: label, type: type, customTypeName: customTypeName);

  static const remove = _NodeAction._(isDelete: true);

  final String? label;
  final MapNodeType type;
  final String? customTypeName;
  final bool isDelete;
}

class _SpotLabelDialog extends StatefulWidget {
  const _SpotLabelDialog({
    required this.title,
    this.initialLabel = '',
    this.initialType = MapNodeType.store,
    this.initialCustomTypeName,
    this.actionLabel = 'Save',
    this.showDelete = false,
  });

  final String title;
  final String initialLabel;
  final MapNodeType initialType;
  final String? initialCustomTypeName;
  final String actionLabel;
  final bool showDelete;

  @override
  State<_SpotLabelDialog> createState() => _SpotLabelDialogState();
}

class _SpotLabelDialogState extends State<_SpotLabelDialog> {
  late final TextEditingController _controller;
  late final TextEditingController _customTypeController;
  late MapNodeType _type;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialLabel);
    _customTypeController = TextEditingController(
      text: widget.initialCustomTypeName ?? '',
    );
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _controller.dispose();
    _customTypeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: _allowsEmptyNodeName(_type)
                ? 'Spot name (optional)'
                : 'Spot name',
            hintText: _allowsEmptyNodeName(_type)
                ? 'Leave blank for an unnamed ${_nodeTypeLabel(_type).toLowerCase()}'
                : 'e.g. Main entrance',
          ),
          onSubmitted: (value) => Navigator.pop(
            context,
            _NodeAction.rename(
              value.trim(),
              _type,
              _customTypeController.text.trim(),
            ),
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<MapNodeType>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Spot type'),
          items: MapNodeType.values
              .where((type) => type != MapNodeType.place)
              .map(
                (type) => DropdownMenuItem(
                  value: type,
                  child: Row(
                    children: [
                      Icon(_nodeTypeIcon(type), size: 18),
                      const SizedBox(width: 9),
                      Text(_nodeTypeLabel(type)),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: (type) {
            if (type != null) setState(() => _type = type);
          },
        ),
        if (_type == MapNodeType.custom) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _customTypeController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Custom node type',
              hintText: 'e.g. Restroom',
            ),
          ),
        ],
      ],
    ),
    actions: [
      if (widget.showDelete)
        TextButton(
          onPressed: () => Navigator.pop(context, _NodeAction.remove),
          child: const Text('Delete'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _NodeAction.rename(
            _controller.text.trim(),
            _type,
            _customTypeController.text.trim(),
          ),
        ),
        child: Text(widget.actionLabel),
      ),
    ],
  );
}

String _nodeTypeLabel(MapNodeType type) => switch (type) {
  MapNodeType.pathway => 'Pathway',
  MapNodeType.store => 'Stores',
  MapNodeType.restroom => 'Restroom',
  MapNodeType.elevator => 'Elevators',
  MapNodeType.escalator => 'Escalators',
  MapNodeType.stairs => 'Stairs',
  MapNodeType.custom => 'Custom',
  MapNodeType.place => 'Place',
};

IconData _nodeTypeIcon(MapNodeType type) => switch (type) {
  MapNodeType.pathway => Icons.route_rounded,
  MapNodeType.store => Icons.storefront_outlined,
  MapNodeType.restroom => Icons.wc_rounded,
  MapNodeType.elevator => Icons.elevator_rounded,
  MapNodeType.escalator => Icons.escalator_rounded,
  MapNodeType.stairs => Icons.stairs_rounded,
  MapNodeType.custom => Icons.tune_rounded,
  MapNodeType.place => Icons.place_outlined,
};

bool _allowsEmptyNodeName(MapNodeType type) => const {
  MapNodeType.pathway,
  MapNodeType.restroom,
  MapNodeType.elevator,
  MapNodeType.escalator,
  MapNodeType.stairs,
}.contains(type);
