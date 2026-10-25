import 'package:cloud_firestore/cloud_firestore.dart';

class JobCoordinate {
  const JobCoordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  GeoPoint toGeoPoint() => GeoPoint(latitude, longitude);

  static JobCoordinate? fromGeoPoint(Object? value) {
    if (value is! GeoPoint) return null;
    return JobCoordinate(latitude: value.latitude, longitude: value.longitude);
  }
}

class JobLocationSelection {
  const JobLocationSelection({
    required this.position,
    required this.exactAddress,
    required this.areaLabel,
  });

  final JobCoordinate position;
  final String exactAddress;
  final String areaLabel;

  JobLocationSelection copyWith({
    JobCoordinate? position,
    String? exactAddress,
    String? areaLabel,
  }) => JobLocationSelection(
    position: position ?? this.position,
    exactAddress: exactAddress ?? this.exactAddress,
    areaLabel: areaLabel ?? this.areaLabel,
  );
}

class ExactJobLocation {
  const ExactJobLocation({
    required this.position,
    required this.address,
    this.dropoffPosition,
    this.dropoffAddress,
  });

  /// The job site, or the pickup point for errands.
  final JobCoordinate position;
  final String address;

  /// Errands only.
  final JobCoordinate? dropoffPosition;
  final String? dropoffAddress;

  factory ExactJobLocation.fromMap(Map<String, dynamic> data) {
    final position = JobCoordinate.fromGeoPoint(data['position']);
    if (position == null) {
      throw const FormatException('Exact job location has no valid position.');
    }
    return ExactJobLocation(
      position: position,
      address: (data['address'] ?? '').toString(),
      dropoffPosition: JobCoordinate.fromGeoPoint(data['dropoffPosition']),
      dropoffAddress: data['dropoffAddress']?.toString(),
    );
  }
}
