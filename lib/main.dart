import 'package:flutter/material.dart';

import 'models/mall_map.dart';
import 'screens/create_map_screen.dart';
import 'screens/route_planner_screen.dart';
import 'services/map_store.dart';
import 'widgets/map_preview.dart';

void main() {
  runApp(const AsaApp());
}

class AsaApp extends StatelessWidget {
  const AsaApp({super.key});

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
    home: const AppShell(),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _store = MapStore();
  int _selectedTab = 0;
  List<MallMap> _maps = [];
  bool _loadingMaps = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadMaps();
  }

  Future<void> _loadMaps() async {
    try {
      final maps = await _store.loadMaps();
      if (mounted) {
        setState(() {
          _maps = maps;
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

  Future<void> _createMap() async {
    final created = await Navigator.of(context).push<MallMap>(
      MaterialPageRoute(builder: (_) => CreateMapScreen(store: _store)),
    );
    if (created != null && mounted) {
      setState(() {
        _maps.insert(0, created);
        _selectedTab = 1;
      });
    }
  }

  Future<void> _deleteMap(MallMap map) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete map?'),
        content: Text('“${map.name}” and its saved floor plan will be removed.'),
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
    if (shouldDelete != true || !mounted) return;
    try {
      await _store.deleteMap(map.id);
      if (mounted) setState(() => _maps.removeWhere((item) => item.id == map.id));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete this map: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomeScreen(onOpenMaps: () => setState(() => _selectedTab = 1)),
      _MapsScreen(
        maps: _maps,
        isLoading: _loadingMaps,
        loadError: _loadError,
        onRetry: _loadMaps,
        onCreateMap: _createMap,
        onDeleteMap: _deleteMap,
      ),
      _SettingsScreen(onCreateMap: _createMap),
    ];
    return Scaffold(
      body: IndexedStack(index: _selectedTab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
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
  const _HomeScreen({required this.onOpenMaps});

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
        _RecommendedMapCard(onTap: onOpenMaps),
        const SizedBox(height: 27),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Frequently visited',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(onPressed: onOpenMaps, child: const Text('See all')),
          ],
        ),
        const SizedBox(height: 5),
        _FrequentlyVisitedTile(
          icon: Icons.shopping_bag_outlined,
          title: 'SM Seaside City Cebu',
          subtitle: 'Shopping · Cebu City',
          color: const Color(0xFFE92332),
          onTap: onOpenMaps,
        ),
        _FrequentlyVisitedTile(
          icon: Icons.local_cafe_outlined,
          title: 'Coffee & cafés',
          subtitle: 'Discover places nearby',
          color: const Color(0xFF16885B),
          onTap: onOpenMaps,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onOpenMaps,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Browse all maps'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            foregroundColor: const Color(0xFF25292D),
            side: const BorderSide(color: Color(0xFFE2E5E7)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
      ],
    ),
  );
}

class _RecommendedMapCard extends StatelessWidget {
  const _RecommendedMapCard({required this.onTap});

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
              child: const MapPreview(height: 92, emptyLabel: ''),
            ),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SM Seaside City Cebu',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                SizedBox(height: 6),
                Text(
                  'Your mall, made easy to explore',
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

class _FrequentlyVisitedTile extends StatelessWidget {
  const _FrequentlyVisitedTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
    leading: CircleAvatar(
      backgroundColor: color.withValues(alpha: .11),
      child: Icon(icon, color: color),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    trailing: const Icon(Icons.chevron_right_rounded),
  );
}

class _MapsScreen extends StatelessWidget {
  const _MapsScreen({
    required this.maps,
    required this.isLoading,
    required this.loadError,
    required this.onRetry,
    required this.onCreateMap,
    required this.onDeleteMap,
  });

  final List<MallMap> maps;
  final bool isLoading;
  final String? loadError;
  final VoidCallback onRetry;
  final VoidCallback onCreateMap;
  final ValueChanged<MallMap> onDeleteMap;

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
              IconButton.filledTonal(
                onPressed: onCreateMap,
                tooltip: 'Create map',
                icon: const Icon(Icons.add),
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
                const SizedBox(height: 18),
                _SampleMapCard(onTap: () => _openSampleMap(context)),
                if (maps.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  const Text(
                    'YOUR MAPS',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      color: Color(0xFF878E93),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 11),
                  ...maps.map(
                    (map) => Padding(
                      padding: const EdgeInsets.only(bottom: 13),
                      child: _SavedMapCard(
                        map: map,
                        onTap: () => _openMap(context, map),
                        onDelete: () => onDeleteMap(map),
                      ),
                    ),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 25),
                    child: _EmptyMaps(onCreateMap: onCreateMap),
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
          imagePath: map.imagePath,
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

  void _openSampleMap(BuildContext context) {
    const nodes = [
      MapNode(id: 'entrance', label: 'Main entrance', x: .2, y: .77),
      MapNode(id: 'food-court', label: 'Food court', x: .56, y: .43),
      MapNode(id: 'cinema', label: 'Cinema', x: .82, y: .25),
      MapNode(id: 'sm-store', label: 'SM Store', x: .78, y: .76),
    ];
    const connections = [
      MapConnection(from: 'entrance', to: 'food-court'),
      MapConnection(from: 'food-court', to: 'cinema'),
      MapConnection(from: 'food-court', to: 'sm-store'),
    ];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const RoutePlannerScreen(
          mallName: 'SM Seaside',
          nodes: nodes,
          connections: connections,
        ),
      ),
    );
  }
}

class _SampleMapCard extends StatelessWidget {
  const _SampleMapCard({required this.onTap});

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
            child: const MapPreview(height: 168, emptyLabel: ''),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 12, 6, 3),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SM Seaside City Cebu',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Cebu City · Sample map',
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

class _SavedMapCard extends StatelessWidget {
  const _SavedMapCard({
    required this.map,
    required this.onTap,
    required this.onDelete,
  });

  final MallMap map;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 100,
              height: 82,
              child: MapPreview(
                height: 82,
                imagePath: map.imagePath,
                nodes: map.nodes,
                connections: map.connections,
                emptyLabel: '',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  map.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${map.nodes.length} spots · ${map.connections.length} paths',
                  style: const TextStyle(
                    color: Color(0xFF737B81),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _dateLabel(map.createdAt),
                  style: const TextStyle(
                    color: Color(0xFF92999E),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete ${map.name}',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    ),
  );
}

class _EmptyMaps extends StatelessWidget {
  const _EmptyMaps({required this.onCreateMap});

  final VoidCallback onCreateMap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F8F9),
      borderRadius: BorderRadius.circular(19),
    ),
    child: Column(
      children: [
        const Icon(Icons.add_location_alt_outlined, size: 30),
        const SizedBox(height: 9),
        const Text(
          'Make a map of your own',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        const Text(
          'Upload a floor plan, place spots and draw paths.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF777F85), fontSize: 12),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: onCreateMap, child: const Text('Create map')),
      ],
    ),
  );
}

class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen({required this.onCreateMap});

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
        const Text(
          'Settings',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 23),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F6F7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.person_rounded,
                  size: 31,
                  color: Color(0xFF737B81),
                ),
              ),
              SizedBox(height: 9),
              Text(
                'THE ASA USER',
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
        _SettingsTile(
          icon: Icons.add_location_alt_outlined,
          title: 'Create map',
          onTap: widget.onCreateMap,
        ),
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

String _dateLabel(DateTime date) =>
    'Added ${date.month}/${date.day}/${date.year}';
