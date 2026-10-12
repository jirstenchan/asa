import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../models/mall_map.dart';
import '../services/map_store.dart';
import '../widgets/map_preview.dart';

class CreateMapScreen extends StatefulWidget {
  const CreateMapScreen({super.key, required this.store});

  final MapStore store;

  @override
  State<CreateMapScreen> createState() => _CreateMapScreenState();
}

enum _EditMode { addNode, connect }

class _CreateMapScreenState extends State<CreateMapScreen> {
  final _nameController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _radiusController = TextEditingController(text: '100');
  final _picker = ImagePicker();
  final List<MapNode> _nodes = [];
  final List<MapConnection> _connections = [];
  final List<MapCalibrationPoint> _calibrationPoints = [];
  String? _imagePath;
  String? _selectedNodeId;
  Position? _pendingCalibrationPosition;
  _EditMode _mode = _EditMode.addNode;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  Future<void> _chooseImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (image != null && mounted) {
        setState(() => _imagePath = image.path);
      }
    } catch (error) {
      if (mounted) _showMessage('Could not open your photos: $error');
    }
  }

  Future<void> _addNode(Offset position) async {
    final details = await _askForNodeDetails(title: 'Label this spot');
    final label = details?.label?.trim();
    if (details == null || label == null || label.isEmpty || !mounted) return;
    setState(() {
      _nodes.add(
        MapNode(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          label: label,
          x: position.dx.clamp(.025, .975).toDouble(),
          y: position.dy.clamp(.035, .965).toDouble(),
          type: details.type,
        ),
      );
    });
  }

  Future<void> _captureCalibrationPoint() async {
    if (_imagePath == null) {
      _showMessage('Upload the floor plan before calibrating it.');
      return;
    }
    if (_calibrationPoints.length >= 2) {
      _showMessage('This map already has two GPS reference points.');
      return;
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showMessage('Turn on location services to capture a reference point.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMessage('Location permission is needed to calibrate this map.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _pendingCalibrationPosition = position;
        _mode = _EditMode.addNode;
      });
      _showMessage(
        'Location captured. Tap its matching point on the floor plan.',
      );
    } catch (error) {
      if (mounted) {
        _showMessage('Could not capture a GPS reference point: $error');
      }
    }
  }

  Future<void> _handleCanvasTap(Offset position) async {
    final calibration = _pendingCalibrationPosition;
    if (calibration != null) {
      setState(() {
        _calibrationPoints.add(
          MapCalibrationPoint(
            x: position.dx,
            y: position.dy,
            latitude: calibration.latitude,
            longitude: calibration.longitude,
          ),
        );
        _pendingCalibrationPosition = null;
      });
      _showMessage(
        'GPS reference point ${_calibrationPoints.length} of 2 saved.',
      );
      return;
    }
    await _addNode(position);
  }

  Future<void> _handleNodeTap(MapNode node) async {
    if (_mode == _EditMode.connect) {
      if (_selectedNodeId == null) {
        setState(() => _selectedNodeId = node.id);
        _showMessage('Now tap the next spot to connect to ${node.label}.');
        return;
      }
      if (_selectedNodeId == node.id) {
        setState(() => _selectedNodeId = null);
        return;
      }
      final alreadyConnected = _connections.any(
        (edge) =>
            (edge.from == _selectedNodeId && edge.to == node.id) ||
            (edge.to == _selectedNodeId && edge.from == node.id),
      );
      if (alreadyConnected) {
        _showMessage('Those two spots are already connected.');
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
        initialType: node.type,
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
    } else if (result.label case final String label when label.isNotEmpty) {
      setState(() {
        final index = _nodes.indexWhere((item) => item.id == node.id);
        _nodes[index] = MapNode(
          id: node.id,
          label: label,
          x: node.x,
          y: node.y,
          type: result.type,
        );
      });
    } else {
      _showMessage('Spot names cannot be empty.');
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
    if (_imagePath == null) {
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
        pickedImagePath: _imagePath!,
        nodes: _nodes,
        connections: _connections,
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusMeters,
        calibrationPoints: _calibrationPoints,
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
        title: const Text('Create map'),
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
                onPressed: _chooseImage,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: Text(_imagePath == null ? 'Upload image' : 'Change'),
              ),
            ),
            const SizedBox(height: 10),
            if (_imagePath == null)
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
                height: 230,
                imagePath: _imagePath,
                nodes: _nodes,
                connections: _connections,
                selectedNodeId: _selectedNodeId,
                onCanvasTap: _mode == _EditMode.addNode
                    ? _handleCanvasTap
                    : null,
                onNodeTap: _handleNodeTap,
                emptyLabel: '',
                showControls: true,
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
            OutlinedButton.icon(
              onPressed: _captureCalibrationPoint,
              icon: const Icon(Icons.my_location_rounded, size: 18),
              label: Text(
                _pendingCalibrationPosition == null
                    ? 'Capture GPS reference point'
                    : 'Tap the matching floor-plan point',
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${_calibrationPoints.length}/2 GPS reference points · '
              'needed to place your live dot on the floor plan',
              style: const TextStyle(color: Color(0xFF68727A), fontSize: 11),
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
                      _imagePath == null
                          ? 'Upload a floor plan first. Then tap the map to place labeled spots.'
                          : _mode == _EditMode.addNode
                          ? 'Tap anywhere on the floor plan to add a labeled spot. Tap a spot to rename or delete it.'
                          : _selectedNodeId == null
                          ? 'Tap two spots in order to draw a path between them.'
                          : 'Choose the second spot to finish the connection.',
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
            if (_nodes.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _nodes.map((node) {
                  return InputChip(
                    avatar: Icon(_nodeTypeIcon(node.type), size: 16),
                    label: Text(node.label),
                    onPressed: () => _handleNodeTap(node),
                    onDeleted: () {
                      setState(() {
                        _nodes.remove(node);
                        _connections.removeWhere(
                          (edge) => edge.from == node.id || edge.to == node.id,
                        );
                      });
                    },
                  );
                }).toList(),
              ),
            ],
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
    this.type = MapNodeType.place,
    this.isDelete = false,
  });

  const _NodeAction.rename(String label, MapNodeType type)
    : this._(label: label, type: type);

  static const remove = _NodeAction._(isDelete: true);

  final String? label;
  final MapNodeType type;
  final bool isDelete;
}

class _SpotLabelDialog extends StatefulWidget {
  const _SpotLabelDialog({
    required this.title,
    this.initialLabel = '',
    this.initialType = MapNodeType.place,
    this.actionLabel = 'Save',
    this.showDelete = false,
  });

  final String title;
  final String initialLabel;
  final MapNodeType initialType;
  final String actionLabel;
  final bool showDelete;

  @override
  State<_SpotLabelDialog> createState() => _SpotLabelDialogState();
}

class _SpotLabelDialogState extends State<_SpotLabelDialog> {
  late final TextEditingController _controller;
  late MapNodeType _type;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialLabel);
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _controller.dispose();
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
          decoration: const InputDecoration(
            labelText: 'Spot name',
            hintText: 'e.g. Main entrance',
          ),
          onSubmitted: (value) =>
              Navigator.pop(context, _NodeAction.rename(value.trim(), _type)),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<MapNodeType>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Spot type'),
          items: MapNodeType.values
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
          _NodeAction.rename(_controller.text.trim(), _type),
        ),
        child: Text(widget.actionLabel),
      ),
    ],
  );
}

String _nodeTypeLabel(MapNodeType type) => switch (type) {
  MapNodeType.place => 'Place',
  MapNodeType.elevator => 'Elevator',
  MapNodeType.escalator => 'Escalator',
  MapNodeType.stairs => 'Stairs',
};

IconData _nodeTypeIcon(MapNodeType type) => switch (type) {
  MapNodeType.place => Icons.place_outlined,
  MapNodeType.elevator => Icons.elevator_rounded,
  MapNodeType.escalator => Icons.escalator_rounded,
  MapNodeType.stairs => Icons.stairs_rounded,
};
