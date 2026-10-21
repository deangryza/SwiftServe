import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../../shared/widgets/open_street_map_layers.dart';

class MapTrackingCard extends StatelessWidget {
  const MapTrackingCard({super.key});

  static const LatLng clientLocation = LatLng(14.844100, 120.811900);
  static const LatLng workerLocation = LatLng(14.846000, 120.814500);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: clientLocation,
            initialZoom: 15,
            minZoom: 3,
            maxZoom: 18,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
          ),
          children: [
            const SwiftServeMapTiles(),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: const [workerLocation, clientLocation],
                  color: const Color(0xFF2F80ED),
                  strokeWidth: 5,
                ),
              ],
            ),
            const MarkerLayer(
              markers: [
                Marker(
                  point: clientLocation,
                  width: 48,
                  height: 48,
                  alignment: Alignment.bottomCenter,
                  child: SwiftServeMapPin(label: 'Client location'),
                ),
                Marker(
                  point: workerLocation,
                  width: 42,
                  height: 42,
                  alignment: Alignment.bottomCenter,
                  child: Icon(
                    Icons.person_pin_circle,
                    size: 42,
                    color: Color(0xFF2F80ED),
                  ),
                ),
              ],
            ),
            const SwiftServeMapAttribution(),
          ],
        ),
      ),
    );
  }
}
