import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/job_location.dart';
import 'open_street_map_layers.dart';

LatLng _latLng(JobCoordinate coordinate) =>
    LatLng(coordinate.latitude, coordinate.longitude);

/// Camera fit that keeps every given point on screen.
CameraFit errandCameraFit(List<JobCoordinate> points) => CameraFit.coordinates(
  coordinates: points.map(_latLng).toList(growable: false),
  padding: const EdgeInsets.all(48),
  maxZoom: 16,
);

/// Map layers for an errand: a line from pickup to drop-off, both pins, and
/// the rider when their position is known.
List<Widget> errandMapLayers({
  required JobCoordinate pickup,
  required JobCoordinate dropoff,
  JobCoordinate? rider,
  required Color routeColor,
}) => [
  PolylineLayer(
    polylines: [
      Polyline(
        points: [_latLng(pickup), _latLng(dropoff)],
        color: routeColor,
        strokeWidth: 4,
        pattern: StrokePattern.dashed(segments: const [10, 8]),
      ),
    ],
  ),
  MarkerLayer(
    markers: [
      Marker(
        point: _latLng(pickup),
        width: 48,
        height: 48,
        alignment: Alignment.bottomCenter,
        child: const SwiftServeMapPin(label: 'Pickup point'),
      ),
      Marker(
        point: _latLng(dropoff),
        width: 40,
        height: 40,
        child: const _DropoffMarker(),
      ),
      if (rider != null)
        Marker(
          point: _latLng(rider),
          width: 44,
          height: 44,
          child: const RiderMarker(),
        ),
    ],
  ),
];

class _DropoffMarker extends StatelessWidget {
  const _DropoffMarker();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Drop-off point',
    image: true,
    child: Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF2E7D32), width: 3),
        boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 4)],
      ),
      child: const Icon(Icons.flag, color: Color(0xFF2E7D32), size: 22),
    ),
  );
}

class RiderMarker extends StatelessWidget {
  const RiderMarker({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Rider location',
    image: true,
    child: Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFC72C),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 5)],
      ),
      child: const Icon(
        Icons.delivery_dining,
        color: Color(0xFF242424),
        size: 26,
      ),
    ),
  );
}
