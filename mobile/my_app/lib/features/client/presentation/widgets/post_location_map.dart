import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../shared/models/job_location.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/repositories/service_request_repository.dart';
import '../../../../shared/widgets/errand_map_layers.dart';
import '../../../../shared/widgets/booking_details_cards.dart';
import '../../../../shared/widgets/open_street_map_layers.dart';

/// Read-only map of where a client's post takes place: the job pin, or the
/// pickup and drop-off for errands. Follows the saved pin, so edits show.
class PostLocationMap extends StatefulWidget {
  const PostLocationMap({super.key, required this.request, this.repository});

  final ServiceRequest request;
  final ServiceRequestRepository? repository;

  @override
  State<PostLocationMap> createState() => _PostLocationMapState();
}

class _PostLocationMapState extends State<PostLocationMap> {
  late final _locationStream = (widget.repository ?? ServiceRequestRepository())
      .watchExactLocation(widget.request.id);
  bool _mapFailed = false;
  int _mapErrorCount = 0;
  int _mapReloadVersion = 0;

  void _handleMapTileError(Object error) {
    if (_mapFailed || !mounted) return;
    _mapErrorCount += 1;
    if (_mapErrorCount < 3) return;
    setState(() => _mapFailed = true);
  }

  void _retryMap() {
    setState(() {
      _mapFailed = false;
      _mapErrorCount = 0;
      _mapReloadVersion += 1;
    });
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<ExactJobLocation?>(
    stream: _locationStream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const _MapMessage('Could not load the saved location.');
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SizedBox(
          height: bookingMapPreviewHeight,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final exact = snapshot.data;
      if (exact == null) {
        return const _MapMessage('No location pinned for this post.');
      }
      return _buildMap(context, exact);
    },
  );

  Widget _buildMap(BuildContext context, ExactJobLocation exact) {
    final pickup = exact.position;
    final dropoff = widget.request.isErrand ? exact.dropoffPosition : null;
    final target = LatLng(pickup.latitude, pickup.longitude);
    return Material(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(bookingMapPreviewRadius),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: bookingMapPreviewHeight,
        child: Stack(
          children: [
            Semantics(
              label: dropoff == null
                  ? 'Map showing the job location.'
                  : 'Map showing the pickup and drop-off.',
              child: FlutterMap(
                // Rebuild the camera when the pin moves after an edit.
                key: ValueKey(
                  '${pickup.latitude},${pickup.longitude},'
                  '${dropoff?.latitude},${dropoff?.longitude}',
                ),
                options: MapOptions(
                  initialCenter: target,
                  initialZoom: 16,
                  initialCameraFit: dropoff == null
                      ? null
                      : errandCameraFit([pickup, dropoff]),
                  minZoom: 3,
                  maxZoom: 18,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                ),
                children: [
                  SwiftServeMapTiles(
                    key: ValueKey(_mapReloadVersion),
                    onError: (_, error, _) => _handleMapTileError(error),
                  ),
                  if (dropoff != null)
                    ...errandMapLayers(
                      pickup: pickup,
                      dropoff: dropoff,
                      routeColor: Theme.of(context).colorScheme.onSurface,
                    )
                  else
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: target,
                          width: 48,
                          height: 48,
                          alignment: Alignment.bottomCenter,
                          child: const SwiftServeMapPin(label: 'Job location'),
                        ),
                      ],
                    ),
                  Theme(
                    data: Theme.of(context).copyWith(
                      textTheme: Theme.of(context).textTheme.copyWith(
                        bodySmall: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(fontSize: 10),
                      ),
                    ),
                    child: const SwiftServeMapAttribution(),
                  ),
                ],
              ),
            ),
            if (_mapFailed) MapUnavailableOverlay(onRetry: _retryMap),
          ],
        ),
      ),
    );
  }
}

class _MapMessage extends StatelessWidget {
  const _MapMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
