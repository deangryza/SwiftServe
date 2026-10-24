import 'package:geocoding/geocoding.dart';

import '../models/job_location.dart';

class ResolvedJobAddress {
  const ResolvedJobAddress({
    required this.exactAddress,
    required this.areaLabel,
  });

  final String exactAddress;
  final String areaLabel;
}

abstract interface class JobAddressResolver {
  Future<ResolvedJobAddress> resolve(JobCoordinate coordinate);
}

class JobGeocodingService implements JobAddressResolver {
  JobGeocodingService({Geocoding? geocoding})
    : _geocoding = geocoding ?? Geocoding();

  final Geocoding _geocoding;

  @override
  Future<ResolvedJobAddress> resolve(JobCoordinate coordinate) async {
    final placemarks = await _geocoding.placemarkFromCoordinates(
      coordinate.latitude,
      coordinate.longitude,
    );
    if (placemarks.isEmpty) {
      throw StateError('No address was found for this pin.');
    }
    final placemark = placemarks.first;
    final exactParts = <String?>[
      placemark.street,
      placemark.subLocality,
      placemark.locality,
      placemark.subAdministrativeArea,
      placemark.administrativeArea,
      placemark.postalCode,
    ];
    // Barangay first, so nearby pickup and drop-off areas read differently.
    final areaParts = <String?>[
      placemark.subLocality,
      placemark.locality,
      placemark.subAdministrativeArea,
      placemark.administrativeArea,
    ];
    return ResolvedJobAddress(
      exactAddress: _uniqueParts(exactParts).join(', '),
      areaLabel: _uniqueParts(areaParts).take(2).join(', '),
    );
  }

  List<String> _uniqueParts(Iterable<String?> parts) {
    final values = <String>[];
    for (final part in parts) {
      final value = part?.trim() ?? '';
      if (value.isNotEmpty && !values.contains(value)) values.add(value);
    }
    return values;
  }
}
