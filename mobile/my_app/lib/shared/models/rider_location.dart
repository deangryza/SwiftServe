import 'package:cloud_firestore/cloud_firestore.dart';

import 'job_location.dart';

/// The assigned rider's latest position during an errand.
class RiderLocation {
  const RiderLocation({
    required this.position,
    this.heading,
    this.speed,
    this.updatedAt,
  });

  final JobCoordinate position;
  final double? heading;
  final double? speed;
  final DateTime? updatedAt;

  static RiderLocation? fromMap(Map<String, dynamic>? data) {
    final position = JobCoordinate.fromGeoPoint(data?['position']);
    if (data == null || position == null) return null;
    return RiderLocation(
      position: position,
      heading: (data['heading'] as num?)?.toDouble(),
      speed: (data['speed'] as num?)?.toDouble(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
