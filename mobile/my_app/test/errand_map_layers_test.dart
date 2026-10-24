import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/widgets/errand_map_layers.dart';

void main() {
  const pickup = JobCoordinate(latitude: 14.84, longitude: 120.81);
  const dropoff = JobCoordinate(latitude: 14.85, longitude: 120.82);

  test('approximate errand shows areas without a route line', () {
    final layers = errandMapLayers(
      pickup: pickup,
      dropoff: dropoff,
      routeColor: Colors.black,
      approximate: true,
    );

    expect(layers.whereType<CircleLayer>(), hasLength(1));
    expect(layers.whereType<PolylineLayer>(), isEmpty);
  });

  test('exact errand shows the route line and pins', () {
    final layers = errandMapLayers(
      pickup: pickup,
      dropoff: dropoff,
      routeColor: Colors.black,
    );

    expect(layers.whereType<PolylineLayer>(), hasLength(1));
    expect(layers.whereType<CircleLayer>(), isEmpty);
  });
}
