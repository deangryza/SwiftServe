import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/services/road_route_service.dart';

void main() {
  const pickup = JobCoordinate(latitude: 14.84, longitude: 120.81);
  const dropoff = JobCoordinate(latitude: 14.85, longitude: 120.82);

  test('reads the route and asks the backend only once', () async {
    var calls = 0;
    final service = RoadRouteService(
      idToken: () async => 'token',
      client: MockClient((request) async {
        calls += 1;
        expect(request.url.path, '/api/routes/errand');
        expect(request.headers['Authorization'], 'Bearer token');
        expect(jsonDecode(request.body), {
          'from': {'lat': 14.84, 'lng': 120.81},
          'to': {'lat': 14.85, 'lng': 120.82},
        });
        return http.Response(
          jsonEncode({
            'points': [
              [14.84, 120.81],
              [14.845, 120.815],
              [14.85, 120.82],
            ],
            'distanceMeters': 1800,
            'durationSeconds': 300,
          }),
          200,
        );
      }),
    );

    final route = await service.fetch(pickup, dropoff);
    await service.fetch(pickup, dropoff);

    expect(route!.points, hasLength(3));
    expect(route.points[1].latitude, 14.845);
    expect(route.distanceMeters, 1800);
    expect(calls, 1);
  });

  test('returns null when routing fails and tries again later', () async {
    var calls = 0;
    final service = RoadRouteService(
      idToken: () async => 'token',
      client: MockClient((_) async {
        calls += 1;
        return http.Response('{"code":"ROUTING_UNAVAILABLE"}', 502);
      }),
    );

    expect(await service.fetch(pickup, dropoff), isNull);
    expect(await service.fetch(pickup, dropoff), isNull);
    expect(calls, 2);
  });

  test('skips the call when nobody is signed in', () async {
    final service = RoadRouteService(
      idToken: () async => null,
      client: MockClient((_) async => fail('should not call the backend')),
    );

    expect(await service.fetch(pickup, dropoff), isNull);
  });
}
