import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:my_app/shared/services/job_geocoding_service.dart';
import 'package:my_app/shared/models/job_location.dart';

class _Geocoder extends Fake implements Geocoding {
  final searches = <String>[];
  bool noResults = false;
  bool offline = false;
  bool reverseFails = false;
  Placemark placemark = const Placemark(
    street: 'Greenbelt',
    locality: 'Makati',
  );

  @override
  Future<List<Location>> locationFromAddress(
    String address, {
    Locale? locale,
  }) async {
    searches.add(address);
    if (offline) throw const SocketException('offline');
    if (noResults) return [];
    return [const Location(latitude: 14.5532, longitude: 121.0214)];
  }

  @override
  Future<List<Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude, {
    Locale? locale,
  }) async {
    expect(latitude, 14.5532);
    expect(longitude, 121.0214);
    if (reverseFails) throw const SocketException('reverse offline');
    return [placemark];
  }
}

void main() {
  test(
    'reverse lookup exposes address components without inventing missing values',
    () async {
      final geocoder = _Geocoder()
        ..placemark = const Placemark(
          street: '123 Example Street',
          subLocality: 'Bulihan',
          locality: 'Malolos',
          subAdministrativeArea: 'Bulacan',
          administrativeArea: 'Central Luzon',
        );
      final service = JobGeocodingService(geocoding: geocoder);
      const coordinate = JobCoordinate(latitude: 14.5532, longitude: 121.0214);
      final address = await service.resolve(coordinate);
      expect(address.barangay, 'Bulihan');
      expect(address.cityMunicipality, 'Malolos');
      expect(address.province, 'Bulacan');
      geocoder.placemark = const Placemark(
        locality: 'Malolos',
        administrativeArea: 'Central Luzon',
      );
      final incomplete = await service.resolve(coordinate);
      expect(incomplete.barangay, isEmpty);
      expect(incomplete.province, isEmpty);
    },
  );
  test(
    'forward lookup returns coordinates and a separate public area label',
    () async {
      final geocoder = _Geocoder();
      final service = JobGeocodingService(geocoding: geocoder);
      final selected = await service.search('  Greenbelt, Makati  ');
      expect(geocoder.searches, ['Greenbelt, Makati']);
      expect(selected.position.latitude, 14.5532);
      expect(selected.position.longitude, 121.0214);
      expect(selected.exactAddress, 'Greenbelt, Makati');
      expect(selected.areaLabel, 'Makati');
    },
  );

  test('empty input makes no provider request', () async {
    final geocoder = _Geocoder();
    await expectLater(
      JobGeocodingService(geocoding: geocoder).search('  '),
      throwsArgumentError,
    );
    expect(geocoder.searches, isEmpty);
  });

  test('no matches never invents coordinates', () async {
    final geocoder = _Geocoder()..noResults = true;
    await expectLater(
      JobGeocodingService(geocoding: geocoder).search('Unknown place'),
      throwsStateError,
    );
  });

  test('forward network failures are reported to the picker', () async {
    final geocoder = _Geocoder()..offline = true;
    await expectLater(
      JobGeocodingService(geocoding: geocoder).search('Greenbelt'),
      throwsA(isA<SocketException>()),
    );
  });

  test(
    'reverse failure retains resolved coordinates and keeps the query private',
    () async {
      final geocoder = _Geocoder()..reverseFails = true;
      final selected = await JobGeocodingService(
        geocoding: geocoder,
      ).search('Private apartment address');
      expect(selected.position.latitude, 14.5532);
      expect(selected.position.longitude, 121.0214);
      expect(selected.exactAddress, 'Private apartment address');
      expect(selected.areaLabel, 'Pinned service area');
    },
  );
}
