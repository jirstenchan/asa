import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/mall_map.dart';
import 'screens/create_map_screen.dart';
import 'screens/route_planner_screen.dart';
import 'services/map_store.dart';
import 'widgets/map_preview.dart';

const _supabaseUrl = 'https://vytgpmznlovjmntmiglj.supabase.co';
const _supabasePublishableKey =
    'sb_publishable_FU6i8PSKoKJUQhaibw4-8g_q2tUxHeE';

abstract interface class AdminAuthService {
  bool get isAdminSignedIn;
  Future<bool> signIn(String email, String password);
  Future<void> signOut();
}

class SupabaseAdminAuthService implements AdminAuthService {
  SupabaseAdminAuthService(this._client);

  final SupabaseClient _client;

  @override
  bool get isAdminSignedIn => _client.auth.currentUser != null;

  @override
  Future<bool> signIn(String email, String password) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    return response.user != null;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}

final _sampleMallMap = MallMap(
  id: MapStore.sampleMallMapId,
  name: 'SM Seaside City Cebu',
  imagePath: '',
  floors: const [MapFloor(id: 'ground', name: 'Floor 1', imagePath: '')],
  nodes: const [
    MapNode(
      id: 'entrance',
      label: 'Main entrance',
      x: .2,
      y: .77,
      floorId: 'ground',
    ),
    MapNode(
      id: 'food-court',
      label: 'Food court',
      x: .56,
      y: .43,
      floorId: 'ground',
    ),
    MapNode(id: 'cinema', label: 'Cinema', x: .82, y: .25, floorId: 'ground'),
    MapNode(
      id: 'sm-store',
      label: 'SM Store',
      x: .78,
      y: .76,
      floorId: 'ground',
    ),
  ],
  connections: const [
    MapConnection(from: 'entrance', to: 'food-court'),
    MapConnection(from: 'food-court', to: 'cinema'),
    MapConnection(from: 'food-court', to: 'sm-store'),
  ],
  createdAt: DateTime.utc(2026),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabasePublishableKey,
    );
    runApp(const AsaApp());
  } catch (error) {
    runApp(_StartupErrorApp(error: error));
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not initialize the app: $error'),
        ),
      ),
    ),
  );
}

class AsaApp extends StatelessWidget {
  const AsaApp({super.key, this.adminAuth});

  final AdminAuthService? adminAuth;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ASA Cebu',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFE92332),
        primary: const Color(0xFFE92332),
        surface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF5F6F7),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF111315),
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: const StadiumBorder(),
        ),
      ),
    ),
    home: AppShell(adminAuth: adminAuth),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.adminAuth});

  final AdminAuthService? adminAuth;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _store = MapStore();
  late final AdminAuthService _adminAuth =
      widget.adminAuth ?? SupabaseAdminAuthService(Supabase.instance.client);
  int _selectedTab = 0;
  List<MallMap> _maps = [];
  bool _loadingMaps = true;
  String? _loadError;
  int _settingsTapCount = 0;
  bool _isAdmin = false;
  bool _loadingAdminSession = true;
  bool _sampleMallMapDeleted = false;

  List<MallMap> get _availableMaps => [
    if (!_sampleMallMapDeleted)
      _maps.firstWhere(
        (map) => map.id == _sampleMallMap.id,
        orElse: () => _sampleMallMap,
      ),
    ..._maps.where((map) => map.id != _sampleMallMap.id),
  ];

  @override
  void initState() {
    super.initState();
    _loadMaps();
  }

  Future<void> _loadMaps() async {
    if (mounted) {
      setState(() {
        _isAdmin = _adminAuth.isAdminSignedIn;
        _loadingAdminSession = false;
      });
    }

    try {
      final maps = await _store.loadMaps();
      final sampleMallMapDeleted = await _store.isSampleMallMapDeleted();
      if (mounted) {
        setState(() {
          _maps = maps;
          _sampleMallMapDeleted = sampleMallMapDeleted;
          _loadingMaps = false;
          _loadError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadingMaps = false;
          _loadError = 'Saved maps could not be loaded: $error';
        });
      }
    }
  }

  Future<void> _openMapEditor({MallMap? existingMap}) async {
    final created = await Navigator.of(context).push<MallMap>(
      MaterialPageRoute(
        builder: (_) => CreateMapScreen(store: _store, initialMap: existingMap),
      ),
    );
    if (created != null && mounted) {
      setState(() {
        final index = _maps.indexWhere((map) => map.id == created.id);
        if (index < 0) {
          _maps.insert(0, created);
        } else {
          _maps[index] = created;
        }
      });
    }
  }

  Future<void> _createMap() => _openMapEditor();

  Future<void> _editMap(MallMap map) => _openMapEditor(existingMap: map);

  void _openAdminMaps() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _AdminMapListScreen(
          maps: [
            if (!_sampleMallMapDeleted)
              _maps.firstWhere(
                (map) => map.id == _sampleMallMap.id,
                orElse: () => _sampleMallMap,
              ),
            ..._maps.where((map) => map.id != _sampleMallMap.id),
          ],
          isLoading: _loadingMaps,
          loadError: _loadError,
          onRetry: _loadMaps,
          onEditMap: _editMap,
          onDeleteMap: _deleteMap,
        ),
      ),
    );
  }

  void _registerSettingsTap() {
    if (_isAdmin || _loadingAdminSession) return;
    _settingsTapCount++;
    if (_settingsTapCount >= 10) {
      _settingsTapCount = 0;
      _showAdminLogin();
    }
  }

  void _selectTab(int index) {
    if (index == 2) {
      _registerSettingsTap();
    } else {
      _settingsTapCount = 0;
    }
    setState(() => _selectedTab = index);
  }

  Future<void> _showAdminLogin() async {
    final signedIn = await showDialog<bool>(
      context: context,
      builder: (_) => _AdminLoginDialog(onLogin: _adminAuth.signIn),
    );
    if (!mounted || signedIn != true) return;
    if (_adminAuth.isAdminSignedIn) {
      setState(() => _isAdmin = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Admin mode enabled.')));
    }
  }

  Future<void> _logoutAdmin() async {
    try {
      await _adminAuth.signOut();
      if (mounted) setState(() => _isAdmin = false);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not log out of admin mode: $error')),
        );
      }
    }
  }

  Future<bool> _deleteMap(MallMap map) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete map?'),
        content: Text(
          '“${map.name}” and its saved floor plan will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return false;
    try {
      await _store.deleteMap(map.id);
      final maps = await _store.loadMaps();
      final sampleMallMapDeleted = await _store.isSampleMallMapDeleted();
      if (mounted) {
        setState(() {
          _maps = maps;
          _sampleMallMapDeleted = sampleMallMapDeleted;
        });
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete this map: $error')),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomeScreen(
        maps: _availableMaps,
        onOpenMaps: () => setState(() => _selectedTab = 1),
      ),
      _MapsScreen(
        key: ValueKey(_maps.map((map) => map.id).join('|')),
        maps: _maps.where((map) => map.id != _sampleMallMap.id).toList(),
        sampleMap: _sampleMallMapDeleted
            ? null
            : _maps.firstWhere(
                (map) => map.id == _sampleMallMap.id,
                orElse: () => _sampleMallMap,
              ),
        isLoading: _loadingMaps,
        loadError: _loadError,
        onRetry: _loadMaps,
      ),
      _SettingsScreen(
        isAdmin: _isAdmin,
        onSettingsTap: _registerSettingsTap,
        onAdminLogout: _logoutAdmin,
        onOpenMaps: _openAdminMaps,
        onCreateMap: _createMap,
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: _selectedTab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: _selectTab,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFFFE8EA),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({required this.maps, required this.onOpenMaps});

  final List<MallMap> maps;
  final VoidCallback onOpenMaps;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFFE92332),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.place, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'asa',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: onOpenMaps,
              tooltip: 'Explore maps',
              icon: const Icon(Icons.search_rounded),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          height: 234,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF073F63), Color(0xFF167C99), Color(0xFF42A5A2)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                bottom: -28,
                child: Icon(
                  Icons.location_city_rounded,
                  size: 180,
                  color: Colors.white.withValues(alpha: .13),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WELCOME TO',
                    style: TextStyle(
                      color: Colors.white70,
                      letterSpacing: 3,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'CEBU',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 34,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const SizedBox(
                    width: 205,
                    child: Text(
                      'Find your way around your favorite places.',
                      style: TextStyle(color: Colors.white, height: 1.35),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: onOpenMaps,
                    icon: const Icon(Icons.explore_outlined, size: 18),
                    label: const Text('Explore maps'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF124E68),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        _SectionTitle(
          title: 'Recommended for you',
          action: 'See all',
          onTap: onOpenMaps,
        ),
        const SizedBox(height: 13),
        if (maps.isEmpty)
          const Text(
            'There aren’t any malls available yet.',
            style: TextStyle(color: Color(0xFF737B81)),
          )
        else
          ...maps.map(
            (map) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RecommendedMapCard(map: map, onTap: onOpenMaps),
            ),
          ),
      ],
    ),
  );
}

class _RecommendedMapCard extends StatelessWidget {
  const _RecommendedMapCard({required this.map, required this.onTap});

  final MallMap map;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(19),
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F7),
        borderRadius: BorderRadius.circular(19),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            height: 92,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: MapPreview(
                height: 92,
                imagePath: map.imagePath.isEmpty ? null : map.imagePath,
                floorId: map.effectiveFloors.first.id,
                emptyLabel: '',
                fillImageWidth: true,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  map.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                SizedBox(height: 6),
                Text(
                  '${map.effectiveFloors.length} '
                  'floor${map.effectiveFloors.length == 1 ? '' : 's'} · '
                  '${map.nodes.length} spots',
                  style: TextStyle(color: Color(0xFF777F85), fontSize: 12),
                ),
                SizedBox(height: 7),
                Row(
                  children: [
                    Icon(
                      Icons.near_me_outlined,
                      size: 14,
                      color: Color(0xFFE92332),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'View mall map',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF80878D)),
        ],
      ),
    ),
  );
}

class _MapsScreen extends StatelessWidget {
  const _MapsScreen({
    super.key,
    required this.maps,
    required this.sampleMap,
    required this.isLoading,
    required this.loadError,
    required this.onRetry,
  });

  final List<MallMap> maps;
  final MallMap? sampleMap;
  final bool isLoading;
  final String? loadError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 19, 20, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Maps',
                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
        if (loadError != null)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(loadError!),
                TextButton(onPressed: onRetry, child: const Text('Try again')),
              ],
            ),
          )
        else if (isLoading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                const Text(
                  'Find your way, one stop at a time.',
                  style: TextStyle(color: Color(0xFF737B81)),
                ),
                if (sampleMap != null) ...[
                  const SizedBox(height: 18),
                  _SampleMapCard(
                    map: sampleMap!,
                    onTap: () => _openMap(context, sampleMap!),
                  ),
                ],
                if (maps.isNotEmpty) ...[
                  if (sampleMap != null) const SizedBox(height: 18),
                  ...maps.map(
                    (map) => Padding(
                      padding: const EdgeInsets.only(bottom: 13),
                      child: _SampleMapCard(
                        map: map,
                        onTap: () => _openMap(context, map),
                      ),
                    ),
                  ),
                ],
                if (maps.isEmpty && sampleMap == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 25),
                    child: const Text(
                      'There aren’t any maps available yet.',
                      style: TextStyle(color: Color(0xFF737B81)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );

  void _openMap(BuildContext context, MallMap map) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoutePlannerScreen(
          mallName: map.name,
          imagePath: map.imagePath.isEmpty ? null : map.imagePath,
          floors: map.effectiveFloors,
          nodes: map.nodes,
          connections: map.connections,
          latitude: map.latitude,
          longitude: map.longitude,
          radiusMeters: map.radiusMeters,
          calibrationPoints: map.calibrationPoints,
        ),
      ),
    );
  }
}

class _SampleMapCard extends StatelessWidget {
  const _SampleMapCard({required this.map, required this.onTap});

  final MallMap map;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(21),
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F6),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: MapPreview(
              height: 168,
              imagePath: map.imagePath.isEmpty ? null : map.imagePath,
              floorId: map.effectiveFloors.first.id,
              emptyLabel: 'Floor plan is not available yet',
              fillImageWidth: true,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(6, 12, 6, 3),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        map.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Cebu City · ${map.effectiveFloors.length} floor'
                        '${map.effectiveFloors.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: Color(0xFF777F85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_rounded),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _AdminMapCard extends StatelessWidget {
  const _AdminMapCard({
    required this.map,
    required this.onEdit,
    required this.onDelete,
  });

  final MallMap map;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF4F5F6),
      borderRadius: BorderRadius.circular(21),
    ),
    child: Column(
      children: [
        InkWell(
          key: Key('admin-map-${map.id}'),
          onTap: onEdit,
          borderRadius: BorderRadius.circular(21),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: MapPreview(
                    height: 168,
                    imagePath: map.imagePath.isEmpty ? null : map.imagePath,
                    floorId: map.effectiveFloors.first.id,
                    emptyLabel: 'Upload a floor plan to preview this map',
                    fillImageWidth: true,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 12, 6, 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              map.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${map.effectiveFloors.length} '
                              'floor${map.effectiveFloors.length == 1 ? '' : 's'}'
                              ' · ${map.nodes.length} nodes',
                              style: const TextStyle(
                                color: Color(0xFF777F85),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 5),
            child: TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Delete map'),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            ),
          ),
        ),
      ],
    ),
  );
}

class _AdminMapListScreen extends StatefulWidget {
  const _AdminMapListScreen({
    required this.maps,
    required this.isLoading,
    required this.loadError,
    required this.onRetry,
    required this.onEditMap,
    required this.onDeleteMap,
  });

  final List<MallMap> maps;
  final bool isLoading;
  final String? loadError;
  final VoidCallback onRetry;
  final Future<void> Function(MallMap) onEditMap;
  final Future<bool> Function(MallMap) onDeleteMap;

  @override
  State<_AdminMapListScreen> createState() => _AdminMapListScreenState();
}

class _AdminMapListScreenState extends State<_AdminMapListScreen> {
  late List<MallMap> _maps = widget.maps;

  @override
  void didUpdateWidget(covariant _AdminMapListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.maps, widget.maps)) _maps = widget.maps;
  }

  Future<void> _deleteMap(MallMap map) async {
    final deleted = await widget.onDeleteMap(map);
    if (deleted && mounted) {
      setState(() => _maps.removeWhere((item) => item.id == map.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Maps'),
      leading: IconButton(
        tooltip: 'Go back',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
      ),
    ),
    body: SafeArea(
      child: widget.isLoading
          ? const Center(child: CircularProgressIndicator())
          : widget.loadError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(widget.loadError!),
                  ),
                  TextButton(
                    onPressed: widget.onRetry,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                const Text(
                  'Select a map to edit it.',
                  style: TextStyle(color: Color(0xFF737B81)),
                ),
                const SizedBox(height: 18),
                for (final map in _maps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 13),
                    child: _AdminMapCard(
                      map: map,
                      onEdit: () => widget.onEditMap(map),
                      onDelete: () => _deleteMap(map),
                    ),
                  ),
              ],
            ),
    ),
  );
}

class _AdminLoginDialog extends StatefulWidget {
  const _AdminLoginDialog({required this.onLogin});

  final Future<bool> Function(String email, String password) onLogin;

  @override
  State<_AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends State<_AdminLoginDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _signingIn = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Admin login'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('admin-email'),
            controller: _emailController,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(labelText: 'Gmail'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('admin-password'),
            controller: _passwordController,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => _signIn(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _signingIn ? null : _signIn,
        child: Text(_signingIn ? 'Signing in…' : 'Sign in'),
      ),
    ],
  );

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your Gmail and password.');
      return;
    }
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      final signedIn = await widget.onLogin(email, password);
      if (!mounted) return;
      if (signedIn) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _signingIn = false;
          _error = 'Supabase did not return a signed-in account.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _signingIn = false;
        _error =
            'Sign-in failed. Check your Gmail and password, then try again.';
      });
    }
  }
}

class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen({
    required this.isAdmin,
    required this.onSettingsTap,
    required this.onAdminLogout,
    required this.onOpenMaps,
    required this.onCreateMap,
  });

  final bool isAdmin;
  final VoidCallback onSettingsTap;
  final VoidCallback onAdminLogout;
  final VoidCallback onOpenMaps;
  final VoidCallback onCreateMap;

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  bool _notificationsEnabled = true;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      children: [
        InkWell(
          onTap: widget.onSettingsTap,
          child: const Text(
            'Settings',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 23),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F6F7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: Colors.white,
                child: Icon(
                  widget.isAdmin
                      ? Icons.admin_panel_settings_rounded
                      : Icons.person_rounded,
                  size: 31,
                  color: Color(0xFF737B81),
                ),
              ),
              SizedBox(height: 9),
              Text(
                widget.isAdmin ? 'THE ASA ADMIN' : 'THE ASA USER',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              SizedBox(height: 4),
              Text(
                'Make every trip easier.',
                style: TextStyle(color: Color(0xFF8A9196), fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SettingsTile(
          icon: Icons.notifications_none_rounded,
          title: 'Notifications',
          trailing: Switch(
            value: _notificationsEnabled,
            onChanged: (enabled) {
              setState(() => _notificationsEnabled = enabled);
            },
          ),
          onTap: () {},
        ),
        _SettingsTile(
          icon: Icons.flag_outlined,
          title: 'Report issue',
          onTap: () => _showReportDialog(context),
        ),
        _SettingsTile(
          icon: Icons.help_outline_rounded,
          title: 'Frequently asked questions',
          onTap: () => _showInfoDialog(context, 'Frequently asked questions'),
        ),
        _SettingsTile(
          icon: Icons.info_outline_rounded,
          title: 'About',
          onTap: () => _showInfoDialog(context, 'About ASA'),
        ),
        if (widget.isAdmin) ...[
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Text(
              'ADMIN',
              style: TextStyle(
                color: Color(0xFF92999E),
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.map_outlined,
            title: 'Maps',
            onTap: widget.onOpenMaps,
          ),
          _SettingsTile(
            icon: Icons.add_location_alt_outlined,
            title: 'Add map',
            onTap: widget.onCreateMap,
          ),
          _SettingsTile(
            key: const Key('admin-logout'),
            icon: Icons.logout_rounded,
            title: 'Log out of admin account',
            onTap: widget.onAdminLogout,
          ),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Divider(height: 1),
        ),
        const Text(
          'ASA CEBU · VERSION 1.0',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF92999E),
            fontSize: 10,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  void _showReportDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _ReportIssueDialog(
        onSubmit: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Thanks for your feedback!')),
          );
        },
      ),
    );
  }

  void _showInfoDialog(BuildContext context, String title) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text(
          'ASA helps you discover places and navigate indoor spaces. '
          'Create a map by uploading a floor plan, adding labeled spots, '
          'and connecting them with paths.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
    leading: Icon(icon, size: 20),
    title: Text(title, style: const TextStyle(fontSize: 13)),
    trailing:
        trailing ??
        const Icon(Icons.chevron_right_rounded, color: Color(0xFF8A9196)),
  );
}

class _ReportIssueDialog extends StatefulWidget {
  const _ReportIssueDialog({required this.onSubmit});

  final VoidCallback onSubmit;

  @override
  State<_ReportIssueDialog> createState() => _ReportIssueDialogState();
}

class _ReportIssueDialogState extends State<_ReportIssueDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Report an issue'),
    content: TextField(
      controller: _controller,
      maxLines: 4,
      decoration: const InputDecoration(hintText: 'Tell us what happened'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          Navigator.pop(context);
          widget.onSubmit();
        },
        child: const Text('Submit'),
      ),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.action,
    required this.onTap,
  });

  final String title;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      TextButton(onPressed: onTap, child: Text(action)),
    ],
  );
}
