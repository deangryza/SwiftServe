import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/models/service_request.dart';
import 'package:my_app/shared/utils/job_location_utils.dart';

void main() {
  test('roundToPublicArea reduces a pin to neighborhood precision', () {
    final rounded = roundToPublicArea(
      const JobCoordinate(latitude: 14.8441, longitude: 120.8119),
    );

    expect(rounded.latitude, 14.84);
    expect(rounded.longitude, 120.81);
  });

  test('distanceMetersBetween calculates Haversine distance', () {
    final distance = distanceMetersBetween(
      const JobCoordinate(latitude: 0, longitude: 0),
      const JobCoordinate(latitude: 0, longitude: 1),
    );

    expect(distance, closeTo(111195, 100));
  });

  test('formatDistance uses meters, kilometers, and approximate prefix', () {
    expect(formatDistance(246), '250 m away');
    expect(formatDistance(2410, approximate: true), '~2.4 km away');
  });

  test('service request parses a public GeoPoint and supports legacy data', () {
    final mapped = ServiceRequest.fromMap('mapped', {
      'areaPosition': const GeoPoint(14.84, 120.81),
    });
    final legacy = ServiceRequest.fromMap('legacy', const {});

    expect(mapped.areaLatitude, 14.84);
    expect(mapped.areaLongitude, 120.81);
    expect(legacy.areaPosition, isNull);
  });

  test('exact location parses its protected GeoPoint contract', () {
    final location = ExactJobLocation.fromMap({
      'position': const GeoPoint(14.8441, 120.8119),
      'address': '123 Example Street',
    });

    expect(location.position.latitude, 14.8441);
    expect(location.address, '123 Example Street');
  });
}
