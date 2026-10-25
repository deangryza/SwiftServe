import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/services/road_route_service.dart';
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

  test('approximate errand shows areas without a route line', () {
    final layers = errandMapLayers(
      pickup: pickup,
      dropoff: dropoff,
      routeColor: Colors.black,
      approximate: true,
    );

    expect(layers.whereType<CircleLayer>(), hasLength(1));
    expect(layers.whereType<ErrandRouteLayer>(), isEmpty);
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
