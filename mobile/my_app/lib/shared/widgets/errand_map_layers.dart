import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/job_location.dart';
import '../utils/job_location_utils.dart';
import '../services/road_route_service.dart';
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

/// Map layers for an errand: the road route from pickup to drop-off, both
/// pins, and the rider when their position is known.
///
/// When [approximate], the points are public areas, so each end is drawn as
/// a small area badge instead of a pin; the route between them is still
/// traced so the rider can judge the trip.
///
/// With [riderLegFrom], the rider's own leg to their next stop (the pickup,
/// or the drop-off when [riderToDropoff]) is drawn as a dashed route, like a
/// ride-hailing job. Pass a throttled point (see `RerouteThrottle`) so the
/// route is not looked up again on every GPS fix; [rider] still moves the
/// marker on every fix.
List<Widget> errandMapLayers({
  required JobCoordinate pickup,
  required JobCoordinate dropoff,
  JobCoordinate? rider,
  required Color routeColor,
  bool approximate = false,
  JobCoordinate? riderLegFrom,
  bool riderToDropoff = false,
  RoadRouteService? routeService,
  ValueChanged<RoadRoute>? onRoute,
  ValueChanged<RoadRoute>? onRiderLeg,
}) => [
  if (riderLegFrom != null)
    ErrandRouteLayer(
      pickup: riderLegFrom,
      dropoff: riderToDropoff ? dropoff : pickup,
      color: riderLegColor,
      service: routeService,
      riderLeg: true,
      onRoute: onRiderLeg,
    ),
  ErrandRouteLayer(
    pickup: pickup,
    dropoff: dropoff,
    color: routeColor,
    service: routeService,
    onRoute: onRoute,
  ),
  if (approximate)
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
        if (rider != null)
          Marker(
            point: _latLng(rider),
            width: 44,
            height: 44,
            child: const RiderMarker(),
          ),
      ],
    )
  else
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

/// Colour of the rider's leg to the pickup, kept quieter than the errand.
const Color riderLegColor = Color(0xFF1E6FD9);

/// The pickup → drop-off line. Follows the real roads once the route is
/// known, and is a dashed straight line until then or when routing fails.
///
/// A [riderLeg] (rider → pickup) is always drawn dashed and thinner.
class ErrandRouteLayer extends StatefulWidget {
  const ErrandRouteLayer({
    super.key,
    required this.pickup,
    required this.dropoff,
    required this.color,
    this.service,
    this.riderLeg = false,
    this.onRoute,
  });

  final JobCoordinate pickup;
  final JobCoordinate dropoff;
  final Color color;
  final RoadRouteService? service;
  final bool riderLeg;

  /// Called once the road route is known, for distance and time labels.
  final ValueChanged<RoadRoute>? onRoute;

  @override
  State<ErrandRouteLayer> createState() => _ErrandRouteLayerState();
}

class _ErrandRouteLayerState extends State<ErrandRouteLayer> {
  RoadRoute? _route;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ErrandRouteLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool moved(JobCoordinate before, JobCoordinate after) =>
        before.latitude != after.latitude ||
        before.longitude != after.longitude;
    // Maps rebuild on every rider update, so compare by value.
    final destinationMoved = moved(oldWidget.dropoff, widget.dropoff);
    if (moved(oldWidget.pickup, widget.pickup) || destinationMoved) {
      // A moving rider keeps their last route on screen while the new one
      // loads, instead of flashing back to a straight line.
      if (!widget.riderLeg || destinationMoved) _route = null;
      _load();
    }
  }

  Future<void> _load() async {
    final version = ++_version;
    final route = await (widget.service ?? RoadRouteService.instance).fetch(
      widget.pickup,
      widget.dropoff,
    );
    if (!mounted || version != _version) return;
    if (route == null && widget.riderLeg && _route != null) return;
    setState(() => _route = route);
    if (route != null) widget.onRoute?.call(route);
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    if (route == null) {
      return PolylineLayer(
        polylines: [
          Polyline(
            points: [_latLng(widget.pickup), _latLng(widget.dropoff)],
            color: widget.color,
            strokeWidth: 4,
            pattern: StrokePattern.dashed(segments: const [10, 8]),
          ),
        ],
      );
    }
    final points = route.points.map(_latLng).toList(growable: false);
    if (widget.riderLeg) {
      return PolylineLayer(
        key: const ValueKey('rider-leg-route'),
        polylines: [
          Polyline(
            points: points,
            color: widget.color,
            strokeWidth: 4,
            strokeCap: StrokeCap.round,
            pattern: StrokePattern.dashed(segments: const [8, 6]),
          ),
        ],
      );
    }
    // A white outline under the line keeps it readable over busy streets.
    return PolylineLayer(
      key: const ValueKey('errand-road-route'),
      polylines: [
        Polyline(
          points: points,
          color: Colors.white,
          strokeWidth: 8,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
        Polyline(
          points: points,
          color: widget.color,
          strokeWidth: 5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      ],
    );
  }
}

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
        border: Border.all(
          color: errandDropoffColor,
          width: 3,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 4,
          ),
        ],
      ),
      child: const Icon(
        Icons.flag,
        color: errandDropoffColor,
        size: 22,
      ),
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
