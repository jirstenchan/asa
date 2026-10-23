import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/main.dart';
import 'package:asa/models/mall_map.dart';
import 'package:asa/screens/create_map_screen.dart';
import 'package:asa/screens/route_planner_screen.dart';
import 'package:asa/services/geo_location.dart';
import 'package:asa/services/map_store.dart';
import 'package:asa/services/route_finder.dart';

class _FakeAdminAuthService implements AdminAuthService {
  bool signedIn = false;

  @override
  bool get isAdminSignedIn => signedIn;

  @override
  Future<bool> signIn(String email, String password) async {
    signedIn = email == 'admin@gmail.com' && password == 'password123';
    return signedIn;
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('map nodes preserve their type and read older place records', () {
    final elevator = MapNode(
      id: 'lift',
      label: 'Elevator',
      x: .5,
      y: .5,
      type: MapNodeType.elevator,
    );
    expect(MapNode.fromJson(elevator.toJson()).type, MapNodeType.elevator);

    final olderRecord = MapNode.fromJson({
      'id': 'old',
      'label': 'Old spot',
      'x': .2,
      'y': .3,
    });
    expect(olderRecord.type, MapNodeType.place);

    final customNode = MapNode(
      id: 'custom',
      label: 'North entrance',
      x: .1,
      y: .2,
      type: MapNodeType.custom,
      floorId: 'level-2',
      customTypeName: 'Entrance',
    );
    final restoredNode = MapNode.fromJson(customNode.toJson());
    expect(restoredNode.type, MapNodeType.custom);
    expect(restoredNode.floorId, 'level-2');
    expect(restoredNode.customTypeName, 'Entrance');
  });

  test('multi-floor connections route through matching vertical nodes', () {
    const nodes = [
      MapNode(id: 'start', label: 'Shop', x: .1, y: .2, floorId: 'level-1'),
      MapNode(
        id: 'lift-1',
        label: 'Elevator',
        x: .5,
        y: .5,
        type: MapNodeType.elevator,
        floorId: 'level-1',
      ),
      MapNode(
        id: 'lift-2',
        label: 'Elevator',
        x: .5,
        y: .5,
        type: MapNodeType.elevator,
        floorId: 'level-2',
      ),
      MapNode(id: 'finish', label: 'Cinema', x: .8, y: .9, floorId: 'level-2'),
    ];
    const connections = [
      MapConnection(from: 'start', to: 'lift-1'),
      MapConnection(from: 'lift-1', to: 'lift-2'),
      MapConnection(from: 'lift-2', to: 'finish'),
    ];

    final route = findRoute(
      nodes: nodes,
      connections: connections,
      from: 'start',
      to: 'finish',
    );
    expect(route?.map((node) => node.id), [
      'start',
      'lift-1',
      'lift-2',
      'finish',
    ]);
  });

  test('map floor records round-trip and legacy maps expose one floor', () {
    final map = MallMap(
      id: 'multi',
      name: 'Multi-level mall',
      imagePath: '/maps/level-1.png',
      floors: const [
        MapFloor(
          id: 'level-1',
          name: 'Level 1',
          imagePath: '/maps/level-1.png',
        ),
        MapFloor(
          id: 'level-2',
          name: 'Level 2',
          imagePath: '/maps/level-2.png',
        ),
      ],
      nodes: const [],
      connections: const [],
      createdAt: DateTime.utc(2026),
    );
    final restored = MallMap.fromJson(map.toJson());
    expect(restored.effectiveFloors.map((floor) => floor.id), [
      'level-1',
      'level-2',
    ]);

    final legacy = MallMap(
      id: 'legacy',
      name: 'Legacy',
      imagePath: '/maps/legacy.png',
      nodes: const [],
      connections: const [],
      createdAt: DateTime.utc(2026),
    );
    expect(legacy.effectiveFloors.single.id, 'ground');
  });

  test(
    'GPS geofence and calibration map real coordinates to map positions',
    () {
      const anchors = [
        MapCalibrationPoint(x: .2, y: .5, latitude: 0, longitude: 0),
        MapCalibrationPoint(x: .8, y: .5, latitude: 0, longitude: .001),
      ];
      expect(
        isInsideGeofence(
          latitude: 0,
          longitude: .0005,
          centerLatitude: 0,
          centerLongitude: .0005,
          radiusMeters: 150,
        ),
        isTrue,
      );
      final position = projectLocationToMap(
        latitude: 0,
        longitude: .0005,
        calibrationPoints: anchors,
      );
      expect(position!.dx, closeTo(.5, .001));
      expect(position.dy, closeTo(.5, .001));
    },
  );

  test('saved user maps can be deleted from local storage', () async {
    final map = MallMap(
      id: 'saved',
      name: 'Saved map',
      imagePath: '/missing/floor-plan.png',
      nodes: const [],
      connections: const [],
      createdAt: DateTime.utc(2026),
    );
    SharedPreferences.setMockInitialValues({
      'asa_saved_maps_v1': '[${jsonEncode(map.toJson())}]',
    });

    final store = MapStore();
    await store.deleteMap(map.id);
    expect(await store.loadMaps(), isEmpty);
  });

  testWidgets('saved maps use the full map card without a delete button', (
    tester,
  ) async {
    final map = MallMap(
      id: 'saved-ui',
      name: 'My mall',
      imagePath: '/missing/floor-plan.png',
      nodes: const [],
      connections: const [],
      createdAt: DateTime.utc(2026),
    );
    SharedPreferences.setMockInitialValues({
      'asa_saved_maps_v1': '[${jsonEncode(map.toJson())}]',
    });
    await tester.pumpWidget(AsaApp(adminAuth: _FakeAdminAuthService()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.map_outlined));
    await tester.pumpAndSettle();

    expect(find.text('My mall'), findsOneWidget);
    expect(find.text('Cebu City · 1 floor'), findsAtLeastNWidgets(2));
    expect(find.byTooltip('Delete My mall'), findsNothing);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    expect(find.byType(RoutePlannerScreen), findsNothing);
  });

  testWidgets('home screen presents the Cebu map discovery experience', (
    tester,
  ) async {
    await tester.pumpWidget(AsaApp(adminAuth: _FakeAdminAuthService()));
    await tester.pumpAndSettle();

    expect(find.text('WELCOME TO'), findsOneWidget);
    expect(find.text('CEBU'), findsOneWidget);
    expect(find.text('Recommended for you'), findsOneWidget);
  });

  testWidgets('map creation stays hidden from regular settings users', (
    tester,
  ) async {
    await tester.pumpWidget(AsaApp(adminAuth: _FakeAdminAuthService()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsAtLeastNWidgets(1));
    expect(find.text('Create map'), findsNothing);
    expect(find.text('MAPS'), findsNothing);
  });

  testWidgets('adding another floor closes name dialog and adds its plan', (
    tester,
  ) async {
    final map = MallMap(
      id: 'floor-editor',
      name: 'Floor editor',
      imagePath: '/missing/floor-1.png',
      floors: const [
        MapFloor(
          id: 'floor-1',
          name: 'Floor 1',
          imagePath: '/missing/floor-1.png',
        ),
      ],
      nodes: const [],
      connections: const [],
      createdAt: DateTime.utc(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CreateMapScreen(
          store: MapStore(),
          initialMap: map,
          pickImagePath: () async => '/missing/floor-2.png',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add floor'));
    await tester.pumpAndSettle();
    expect(find.text('Add a floor'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('floor-name')), 'Floor 2');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Floor 2'), findsOneWidget);
  });

  testWidgets('ten settings taps unlock map management and sample editing', (
    tester,
  ) async {
    final adminAuth = _FakeAdminAuthService();
    await tester.pumpWidget(MaterialApp(home: AppShell(adminAuth: adminAuth)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    for (var tap = 0; tap < 9; tap++) {
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Admin login'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('admin-email')), 'admin@gmail.com');
    await tester.enterText(find.byKey(const Key('admin-password')), 'password123');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(adminAuth.isAdminSignedIn, isTrue);
    await tester.pumpWidget(MaterialApp(home: AppShell(adminAuth: adminAuth)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Maps'), findsOneWidget);
    expect(find.text('Add map'), findsOneWidget);
    expect(find.text('Log out of admin account'), findsOneWidget);
    expect(find.text('THE ASA ADMIN'), findsOneWidget);
    await tester.tap(find.text('Maps').last);
    await tester.pumpAndSettle();
    expect(find.text('Select a map to edit it.'), findsOneWidget);
    expect(find.text('SM Seaside City Cebu'), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin-map-sm_seaside_sample')));
    await tester.pumpAndSettle();
    expect(find.byType(CreateMapScreen), findsOneWidget);
    expect(find.text('Edit map'), findsOneWidget);
    expect(find.text('SM Seaside City Cebu'), findsOneWidget);

    await tester.tap(find.byTooltip('Go back').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Go back').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add map'));
    await tester.pumpAndSettle();
    expect(find.byType(CreateMapScreen), findsOneWidget);
    expect(find.text('Create map'), findsOneWidget);
    await tester.tap(find.byTooltip('Go back').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-logout')));
    await tester.pumpAndSettle();
    expect(adminAuth.isAdminSignedIn, isFalse);
    expect(find.text('Add map'), findsNothing);
    expect(find.text('Log out of admin account'), findsNothing);
  });

  testWidgets(
    'report dialog closes with its text field mounted until dispose',
    (tester) async {
      await tester.pumpWidget(AsaApp(adminAuth: _FakeAdminAuthService()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report issue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A test report');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Report an issue'), findsNothing);

      await tester.tap(find.text('Report issue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Another report');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(find.text('Thanks for your feedback!'), findsOneWidget);
    },
  );

  testWidgets('map library shows the included sample map', (tester) async {
    await tester.pumpWidget(AsaApp(adminAuth: _FakeAdminAuthService()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.map_outlined));
    await tester.pumpAndSettle();

    expect(find.text('SM Seaside City Cebu'), findsOneWidget);
  });

  testWidgets('sample mall plans a route and guides each step', (tester) async {
    await tester.pumpWidget(AsaApp(adminAuth: _FakeAdminAuthService()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.map_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SM Seaside City Cebu'));
    await tester.pumpAndSettle();
    expect(find.text('Plan your route'), findsOneWidget);
    expect(find.text('WHERE ARE YOU NOW?'), findsOneWidget);
    expect(find.text('WHERE DO YOU WANT TO GO?'), findsOneWidget);
    expect(find.text('Your map preview will appear here'), findsNothing);

    final selectors = find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<String>,
    );
    await tester.tap(selectors.at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main entrance').last);
    await tester.pumpAndSettle();

    await tester.tap(selectors.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cinema').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Show route'), 250);
    await tester.tap(find.text('Show route'));
    await tester.pumpAndSettle();
    expect(find.text('2 segments to your destination'), findsOneWidget);
    expect(find.text('Continue to Food court'), findsOneWidget);
    expect(find.text('Arrive at Cinema'), findsOneWidget);

    await tester.tap(find.byTooltip('View full screen'));
    await tester.pumpAndSettle();
    expect(find.text('Map'), findsOneWidget);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    await tester.tap(find.byTooltip('Go back').last);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).last, const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start navigation'));
    await tester.pumpAndSettle();
    expect(
      find.text('This map needs mall GPS coordinates and a radius.'),
      findsOneWidget,
    );
    expect(find.text('Following your live location'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.byTooltip('Go back'));
    await tester.pumpAndSettle();
    expect(find.text('Plan your route'), findsNothing);
  });

  testWidgets('live navigation dot follows device location updates', (
    tester,
  ) async {
    final locationProvider = _FakeLocationProvider(
      _position(latitude: 0, longitude: .0005),
    );
    addTearDown(locationProvider.close);
    const nodes = [
      MapNode(id: 'start', label: 'Start', x: .2, y: .5),
      MapNode(id: 'finish', label: 'Finish', x: .8, y: .5),
    ];
    const connections = [MapConnection(from: 'start', to: 'finish')];
    const anchors = [
      MapCalibrationPoint(x: .2, y: .5, latitude: 0, longitude: 0),
      MapCalibrationPoint(x: .8, y: .5, latitude: 0, longitude: .001),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: RoutePlannerScreen(
          mallName: 'Test mall',
          nodes: nodes,
          connections: connections,
          latitude: 0,
          longitude: .0005,
          radiusMeters: 150,
          calibrationPoints: anchors,
          locationProvider: locationProvider,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final selectors = find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<String>,
    );
    await tester.tap(selectors.at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start').last);
    await tester.pumpAndSettle();
    await tester.tap(selectors.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Show route'), 250);
    await tester.tap(find.text('Show route'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Start navigation'), 250);
    await tester.tap(find.text('Start navigation'));
    await tester.pumpAndSettle();

    expect(find.text('Following your live location'), findsOneWidget);
    expect(find.textContaining('Live location'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    locationProvider.emit(_position(latitude: 0, longitude: .00099));
    await tester.pumpAndSettle();
    expect(find.text("You've arrived!"), findsOneWidget);
    expect(find.text('You are near Finish.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}

class _FakeLocationProvider implements LocationProvider {
  _FakeLocationProvider(this.position);

  Position position;
  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();

  @override
  Future<void> ensurePermission() async {}

  @override
  Future<Position> getCurrentPosition() async => position;

  @override
  Stream<Position> watchPosition() => _controller.stream;

  void emit(Position next) {
    position = next;
    _controller.add(next);
  }

  Future<void> close() => _controller.close();
}

Position _position({required double latitude, required double longitude}) =>
    Position(
      timestamp: DateTime.utc(2026),
      latitude: latitude,
      longitude: longitude,
      accuracy: 4,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
