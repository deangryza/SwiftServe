import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/job_location.dart';
import '../utils/job_location_utils.dart';
import 'open_street_map_layers.dart';

const Color errandPickupColor = Color(0xFF7A5200);
const Color errandDropoffColor = Color(0xFF2E7D32);

LatLng _latLng(JobCoordinate coordinate) =>
    LatLng(coordinate.latitude, coordinate.longitude);

/// Camera fit that keeps every given point on screen.
CameraFit errandCameraFit(List<JobCoordinate> points, {double maxZoom = 16}) =>
    CameraFit.coordinates(
      coordinates: points.map(_latLng).toList(growable: false),
      padding: const EdgeInsets.all(48),
      maxZoom: maxZoom,
    );

/// A shaded circle for a public area point, which is only accurate to within
/// [publicAreaRadiusMeters].
CircleMarker publicAreaCircle(JobCoordinate center, Color color) =>
    CircleMarker(
      point: _latLng(center),
      radius: publicAreaRadiusMeters,
      useRadiusInMeter: true,
      color: color.withValues(alpha: 0.16),
      borderColor: color.withValues(alpha: 0.7),
      borderStrokeWidth: 2,
    );

/// Map layers for an errand: a line from pickup to drop-off, both pins, and
/// the rider when their position is known.
///
/// When [approximate], the points are public areas, so each is drawn as a
/// shaded area instead of a pin and no route line is implied between them.
List<Widget> errandMapLayers({
  required JobCoordinate pickup,
  required JobCoordinate dropoff,
  JobCoordinate? rider,
  required Color routeColor,
  bool approximate = false,
}) => approximate
    ? [
        CircleLayer(
          circles: [
            publicAreaCircle(pickup, errandPickupColor),
            publicAreaCircle(dropoff, errandDropoffColor),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: _latLng(pickup),
              width: 30,
              height: 30,
              child: const ErrandAreaBadge(pickup: true),
            ),
            Marker(
              point: _latLng(dropoff),
              width: 30,
              height: 30,
              child: const ErrandAreaBadge(pickup: false),
            ),
          ],
        ),
      ]
    : [
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

/// Small round icon marking the middle of an approximate pickup or drop-off
/// area. Also used beside the matching heading so the two read together.
class ErrandAreaBadge extends StatelessWidget {
  const ErrandAreaBadge({super.key, required this.pickup, this.size = 30});

  final bool pickup;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = pickup ? errandPickupColor : errandDropoffColor;
    return Semantics(
      label: pickup ? 'Approximate pickup area' : 'Approximate drop-off area',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3)],
        ),
        child: Icon(
          pickup ? Icons.shopping_bag_outlined : Icons.flag,
          color: color,
          size: size * 0.55,
        ),
      ),
    );
  }
}

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
        border: Border.all(color: errandDropoffColor, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 4)],
      ),
      child: const Icon(Icons.flag, color: errandDropoffColor, size: 22),
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
