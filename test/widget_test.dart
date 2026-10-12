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

  testWidgets('home screen presents the Cebu map discovery experience', (
    tester,
  ) async {
    await tester.pumpWidget(const AsaApp());
    await tester.pumpAndSettle();

    expect(find.text('WELCOME TO'), findsOneWidget);
    expect(find.text('CEBU'), findsOneWidget);
    expect(find.text('Recommended for you'), findsOneWidget);
  });

  testWidgets('settings opens the create-map editor', (tester) async {
    await tester.pumpWidget(const AsaApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('Create map'));
    await tester.pumpAndSettle();

    expect(find.text('Name your map'), findsOneWidget);
    expect(find.text('Add a floor plan'), findsOneWidget);
    expect(find.byKey(const Key('mall-latitude')), findsOneWidget);
    expect(find.byKey(const Key('mall-longitude')), findsOneWidget);
    expect(find.byKey(const Key('mall-radius')), findsOneWidget);
    final editorScroll = find.descendant(
      of: find.byType(CreateMapScreen),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Add spots & paths'),
      250,
      scrollable: editorScroll.first,
    );
    expect(find.text('Add spots & paths'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Save map'),
      300,
      scrollable: editorScroll.first,
    );
    expect(find.text('Save map'), findsOneWidget);
  });

  testWidgets(
    'report dialog closes with its text field mounted until dispose',
    (tester) async {
      await tester.pumpWidget(const AsaApp());
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
    await tester.pumpWidget(const AsaApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.map_outlined));
    await tester.pumpAndSettle();

    expect(find.text('SM Seaside City Cebu'), findsOneWidget);
  });

  testWidgets('sample mall plans a route and guides each step', (tester) async {
    await tester.pumpWidget(const AsaApp());
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
