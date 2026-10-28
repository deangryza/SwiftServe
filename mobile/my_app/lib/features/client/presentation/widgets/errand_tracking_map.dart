import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../shared/models/job_location.dart';
import '../../../../shared/models/rider_location.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/repositories/service_request_repository.dart';
import '../../../../shared/services/road_route_service.dart';
import '../../../../shared/utils/job_location_utils.dart';
import '../../../../shared/utils/reroute_throttle.dart';
import '../../../../shared/widgets/errand_map_layers.dart';
import '../../../../shared/widgets/booking_details_cards.dart';
import '../../../../shared/widgets/open_street_map_layers.dart';

/// After this long without an update the rider's position is shown as stale.
const riderLocationStaleAfter = Duration(seconds: 60);

/// Live map of an errand for the client: pickup, drop-off, the rider's
/// position and which stage the errand is in.
class ErrandTrackingMap extends StatefulWidget {
  const ErrandTrackingMap({
    super.key,
    required this.request,
    this.repository,
    this.showTimeline = true,
  });

  final ServiceRequest request;
  final ServiceRequestRepository? repository;
  final bool showTimeline;

  @override
  State<ErrandTrackingMap> createState() => _ErrandTrackingMapState();
}

class _ErrandTrackingMapState extends State<ErrandTrackingMap> {
  late final ServiceRequestRepository _repository =
      widget.repository ?? ServiceRequestRepository();
  final _mapController = MapController();
  ExactJobLocation? _exact;
  bool _followRider = true;
  bool _mapFailed = false;
  int _mapErrorCount = 0;
  int _mapReloadVersion = 0;
  // Rebuilds the "last seen" text while no new position arrives.
  Timer? _clock;
  final _reroute = RerouteThrottle();
  RoadRoute? _riderLeg;
  bool? _legToDropoff;

  void _setRiderLeg(RoadRoute route) {
    if (mounted) setState(() => _riderLeg = route);
  }

  @override
  void initState() {
    super.initState();
    _loadExact();
    _clock = Timer.periodic(
      const Duration(seconds: 15),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadExact() async {
    try {
      final exact = await _repository.getExactLocation(widget.request.id);
      if (mounted) setState(() => _exact = exact);
    } catch (_) {
      // The public, approximate points are still shown.
    }
  }

  void _handleMapTileError(Object error) {
    if (_mapFailed || !mounted) return;
    _mapErrorCount += 1;
    if (_mapErrorCount < 3) return;
    setState(() => _mapFailed = true);
  }

  void _retryMap() => setState(() {
    _mapFailed = false;
    _mapErrorCount = 0;
    _mapReloadVersion += 1;
  });

  void _fitAll(
    JobCoordinate pickup,
    JobCoordinate dropoff,
    JobCoordinate? rider,
  ) {
    setState(() => _followRider = false);
    _mapController.fitCamera(errandCameraFit([pickup, dropoff, ?rider]));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ServiceRequest?>(
      stream: _repository.watchRequest(widget.request.id),
      initialData: widget.request,
      builder: (context, requestSnapshot) {
        final request = requestSnapshot.data ?? widget.request;
        final tracking = request.status == ServiceRequestStatus.ongoing;
        return StreamBuilder<RiderLocation?>(
          stream: tracking
              ? _repository.watchRiderLocation(request.id)
              : const Stream.empty(),
          builder: (context, riderSnapshot) => _buildCard(
            context,
            request,
            tracking ? riderSnapshot.data : null,
          ),
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    ServiceRequest request,
    RiderLocation? rider,
  ) {
    final pickup = _exact?.position ?? request.areaPosition;
    final dropoff = _exact?.dropoffPosition ?? request.dropoffAreaPosition;
    final theme = Theme.of(context);
    if (pickup == null || dropoff == null) {
      return const BookingSectionCard(
        child: Text('Map unavailable for this booking.'),
      );
    }
    final riderPosition = rider?.position;
    final toDropoff =
        request.status == ServiceRequestStatus.ongoing &&
        (request.errandStage?.headsToDropoff ?? false);
    if (_legToDropoff != toDropoff) {
      // A new destination makes the previous leg's ETA meaningless.
      _legToDropoff = toDropoff;
      _riderLeg = null;
    }
    // The leg is only looked up again every ~100 m, not on every update.
    final legFrom = _reroute.update(riderPosition);
    final riderLeg = _riderLeg;
    if (_followRider && riderPosition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(
          LatLng(riderPosition.latitude, riderPosition.longitude),
          _mapController.camera.zoom,
        );
      });
    }

    return Material(
      key: const ValueKey('errand-tracking-map'),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(bookingMapPreviewRadius),
        side: BorderSide(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: bookingMapPreviewHeight,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCameraFit: errandCameraFit([
                      pickup,
                      dropoff,
                      ?riderPosition,
                    ]),
                    minZoom: 3,
                    maxZoom: 18,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    onPositionChanged: (_, hasGesture) {
                      if (hasGesture && _followRider) {
                        setState(() => _followRider = false);
                      }
                    },
                  ),
                  children: [
                    SwiftServeMapTiles(
                      key: ValueKey(_mapReloadVersion),
                      onError: (_, error, _) => _handleMapTileError(error),
                    ),
                    ...errandMapLayers(
                      pickup: pickup,
                      dropoff: dropoff,
                      rider: riderPosition,
                      routeColor: theme.colorScheme.onSurface,
                      riderLegFrom: riderPosition == null ? null : legFrom,
                      riderToDropoff: toDropoff,
                      onRiderLeg: _setRiderLeg,
                    ),
                    Theme(
                      data: theme.copyWith(
                        textTheme: theme.textTheme.copyWith(
                          bodySmall: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                          ),
                        ),
                      ),
                      child: const SwiftServeMapAttribution(),
                    ),
                  ],
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Column(
                    children: [
                      if (riderPosition != null)
                        IconButton.filledTonal(
                          tooltip: 'Follow rider',
                          isSelected: _followRider,
                          onPressed: () => setState(() => _followRider = true),
                          icon: const Icon(Icons.my_location),
                        ),
                      IconButton.filledTonal(
                        tooltip: 'Show whole route',
                        onPressed: () =>
                            _fitAll(pickup, dropoff, riderPosition),
                        icon: const Icon(Icons.zoom_out_map),
                      ),
                    ],
                  ),
                ),
                if (_mapFailed) MapUnavailableOverlay(onRetry: _retryMap),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.showTimeline) ...[
                  ErrandStageTimeline(request: request),
                  const SizedBox(height: 10),
                ],
                Text(
                  riderStatusText(request, rider, DateTime.now()),
                  key: const ValueKey('errand-rider-status'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (riderLeg != null && riderPosition != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${toDropoff ? 'Arriving at drop-off' : 'Arriving at pickup'}'
                    ' · ${formatRouteLeg(riderLeg.distanceMeters, riderLeg.durationSeconds)}',
                    key: const ValueKey('errand-rider-eta'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One line telling the client where the rider is.
String riderStatusText(
  ServiceRequest request,
  RiderLocation? rider,
  DateTime now,
) {
  final riderName = request.workerName ?? 'Your rider';
  switch (request.status) {
    case ServiceRequestStatus.accepted:
      return '$riderName will share their location once they start.';
    case ServiceRequestStatus.completed:
      return 'Delivered.';
    case ServiceRequestStatus.ongoing:
      break;
    case ServiceRequestStatus.pending:
    case ServiceRequestStatus.cancelled:
      return '';
  }
  final updatedAt = rider?.updatedAt;
  if (rider == null || updatedAt == null) {
    return 'Waiting for $riderName\'s location…';
  }
  final age = now.difference(updatedAt);
  if (age < riderLocationStaleAfter) return '$riderName is live on the map.';
  final minutes = age.inMinutes;
  return minutes < 1
      ? 'Last seen less than a minute ago.'
      : 'Last seen $minutes min ago.';
}

class ErrandStageTimeline extends StatelessWidget {
  const ErrandStageTimeline({super.key, required this.request});

  final ServiceRequest request;

  /// How many of the four steps are done, from 0 to 4.
  static int completedSteps(ServiceRequest request) => switch (request.status) {
    ServiceRequestStatus.completed => 4,
    ServiceRequestStatus.ongoing =>
      (request.errandStage ?? ErrandStage.headingToPickup).index + 1,
    _ => 0,
  };

  @override
  Widget build(BuildContext context) {
    final done = completedSteps(request);
    final labels = [
      ...ErrandStage.values.map((stage) => stage.label),
      'Delivered',
    ];
    final theme = Theme.of(context);
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Column(
              children: [
                Icon(
                  i < done ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: i < done
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.outline,
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: i == done - 1 ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
