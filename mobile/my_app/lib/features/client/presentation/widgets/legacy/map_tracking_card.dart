import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapTrackingCard extends StatefulWidget {
  const MapTrackingCard({super.key});

  @override
  State<MapTrackingCard> createState() => _MapTrackingCardState();
}

class _MapTrackingCardState extends State<MapTrackingCard> {
  GoogleMapController? mapController;

  // Markers
  final Set<Marker> markers = {};

  // Polylines
  final Set<Polyline> polylines = {};

  // Sample Locations
  static const LatLng clientLocation = LatLng(14.844100, 120.811900);
  static const LatLng workerLocation = LatLng(14.846000, 120.814500);

  // Initial Camera Position
  static const CameraPosition initialPosition = CameraPosition(
    target: clientLocation,
    zoom: 15,
  );

  @override
  void initState() {
    super.initState();
    loadMarkers();
    loadPolyline();
  }

  void loadMarkers() {
    markers.add(
      const Marker(
        markerId: MarkerId("client"),
        position: clientLocation,
        infoWindow: InfoWindow(title: "Client"),
      ),
    );

    markers.add(
      const Marker(
        markerId: MarkerId("worker"),
        position: workerLocation,
        infoWindow: InfoWindow(title: "Worker"),
      ),
    );
  }

  void loadPolyline() {
    polylines.add(
      const Polyline(
        polylineId: PolylineId("route"),
        color: Color(0xFF2F80ED),
        width: 5,
        points: [workerLocation, clientLocation],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: GoogleMap(
          initialCameraPosition: initialPosition,
          markers: markers,
          polylines: polylines,
          onMapCreated: (GoogleMapController controller) {
            mapController = controller;
          },
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
        ),
      ),
    );
  }
}
