import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/services/road_route_service.dart';
import 'package:my_app/shared/models/service_request.dart';
import 'package:my_app/shared/utils/job_location_utils.dart';
import 'package:my_app/shared/utils/reroute_throttle.dart';
import 'package:my_app/shared/widgets/errand_map_layers.dart';

class _FakeRouteService extends RoadRouteService {
  _FakeRouteService(this.result) : super(idToken: () async => 'token');

  final Future<RoadRoute?> result;
  int calls = 0;

  @override
  Future<RoadRoute?> fetch(JobCoordinate from, JobCoordinate to) {
    calls += 1;
    return result;
  }
}

void main() {
  const pickup = JobCoordinate(latitude: 14.84, longitude: 120.81);
  const dropoff = JobCoordinate(latitude: 14.85, longitude: 120.82);
  const roadRoute = RoadRoute(
    points: [
      pickup,
      JobCoordinate(latitude: 14.845, longitude: 120.811),
      JobCoordinate(latitude: 14.848, longitude: 120.818),
      dropoff,
    ],
    distanceMeters: 1800,
    durationSeconds: 300,
  );

  test('approximate errand traces the route between the areas', () {
    final layers = errandMapLayers(
      pickup: pickup,
      dropoff: dropoff,
      routeColor: Colors.black,
      approximate: true,
    );

    expect(layers.whereType<ErrandRouteLayer>(), hasLength(1));
    expect(layers.whereType<CircleLayer>(), isEmpty);
  });

  test('traces the rider leg to the next stop only when asked', () {
    const rider = JobCoordinate(latitude: 14.83, longitude: 120.80);
    List<ErrandRouteLayer> routes({
      JobCoordinate? legFrom,
      bool toDropoff = false,
    }) => errandMapLayers(
      pickup: pickup,
      dropoff: dropoff,
      rider: rider,
      routeColor: Colors.black,
      approximate: true,
      riderLegFrom: legFrom,
      riderToDropoff: toDropoff,
    ).whereType<ErrandRouteLayer>().toList();

    final toPickup = routes(legFrom: rider);
    expect(toPickup, hasLength(2));
    expect(toPickup.first.riderLeg, isTrue);
    expect(toPickup.first.pickup, rider);
    expect(toPickup.first.dropoff, pickup);
    expect(routes(legFrom: rider, toDropoff: true).first.dropoff, dropoff);
    expect(routes(), hasLength(1));
  });

  group('RerouteThrottle', () {
    const start = JobCoordinate(latitude: 14.84, longitude: 120.81);
    // About 11 m and 222 m north of start.
    const nearby = JobCoordinate(latitude: 14.8401, longitude: 120.81);
    const far = JobCoordinate(latitude: 14.842, longitude: 120.81);

    test('keeps the routed point until the rider moves far enough', () {
      var now = DateTime(2026, 10, 26, 12);
      final throttle = RerouteThrottle(clock: () => now);

      expect(throttle.update(start), start);
      now = now.add(const Duration(minutes: 5));
      expect(throttle.update(nearby), start);
      expect(throttle.update(far), far);
    });

    test('waits the minimum interval even after moving far', () {
      var now = DateTime(2026, 10, 26, 12);
      final throttle = RerouteThrottle(clock: () => now);

      throttle.update(start);
      now = now.add(const Duration(seconds: 5));
      expect(throttle.update(far), start);
      now = now.add(const Duration(seconds: 20));
      expect(throttle.update(far), far);
    });
  });

  test('errand stages after pickup head to the drop-off', () {
    expect(ErrandStage.headingToPickup.headsToDropoff, isFalse);
    expect(ErrandStage.pickedUp.headsToDropoff, isTrue);
    expect(ErrandStage.delivering.headsToDropoff, isTrue);
  });

  test('formats a route leg', () {
    expect(formatRouteLeg(2140, 370), '2.1 km · 6 min');
    expect(formatRouteLeg(640, 20), '640 m · 1 min');
    expect(formatRouteLeg(2140, 370, approximate: true), '~2.1 km · ~6 min');
  });

  test('exact errand shows the route line and pins', () {
    final layers = errandMapLayers(
      pickup: pickup,
      dropoff: dropoff,
      routeColor: Colors.black,
    );

    expect(layers.whereType<ErrandRouteLayer>(), hasLength(1));
    expect(layers.whereType<CircleLayer>(), isEmpty);
  });

  Widget harness(RoadRouteService service) => MaterialApp(
    home: FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(14.845, 120.815),
        initialZoom: 14,
      ),
      children: [
        ErrandRouteLayer(
          pickup: pickup,
          dropoff: dropoff,
          color: Colors.black,
          service: service,
        ),
      ],
    ),
  );

  List<Polyline> drawnLines(WidgetTester tester) => tester
      .widgetList<PolylineLayer>(find.byType(PolylineLayer))
      .expand((layer) => layer.polylines)
      .toList();

  testWidgets('follows the road once the route arrives', (tester) async {
    final service = _FakeRouteService(Future.value(roadRoute));
    await tester.pumpWidget(harness(service));
    await tester.pump();

    expect(find.byKey(const ValueKey('errand-road-route')), findsOneWidget);
    expect(drawnLines(tester).last.points, hasLength(4));
    expect(service.calls, 1);
  });

  testWidgets('reports the route once it arrives', (tester) async {
    RoadRoute? reported;
    await tester.pumpWidget(
      MaterialApp(
        home: FlutterMap(
          options: const MapOptions(
            initialCenter: LatLng(14.845, 120.815),
            initialZoom: 14,
          ),
          children: [
            ErrandRouteLayer(
              pickup: pickup,
              dropoff: dropoff,
              color: Colors.black,
              service: _FakeRouteService(Future.value(roadRoute)),
              onRoute: (route) => reported = route,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(reported, same(roadRoute));
  });

  testWidgets('shows a straight line while loading and on failure', (
    tester,
  ) async {
    final pending = Completer<RoadRoute?>();
    await tester.pumpWidget(harness(_FakeRouteService(pending.future)));

    expect(drawnLines(tester).single.points, hasLength(2));

    pending.complete(null);
    await tester.pump();

    expect(find.byKey(const ValueKey('errand-road-route')), findsNothing);
    expect(drawnLines(tester).single.points, hasLength(2));
  });
}
