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
  Future<JobLocationSelection> search(String address);
}

class JobGeocodingService implements JobAddressResolver {
  JobGeocodingService({Geocoding? geocoding})
    : _geocoding = geocoding ?? Geocoding();

  final Geocoding _geocoding;

  @override
  Future<JobLocationSelection> search(String address) async {
    final query = address.trim();
    if (query.isEmpty) throw ArgumentError.value(address, 'address');
    final locations = await _geocoding.locationFromAddress(query);
    if (locations.isEmpty) {
      throw StateError('No location was found for this address.');
    }
    final first = locations.first;
    final position = JobCoordinate(
      latitude: first.latitude,
      longitude: first.longitude,
    );
    // The pin is valid even if reverse geocoding is temporarily unavailable.
    // Keep precise address text out of the public area label in that case.
    ResolvedJobAddress? resolved;
    try {
      resolved = await resolve(position).timeout(const Duration(seconds: 10));
    } catch (_) {
      // The forward-geocoded coordinate remains usable.
    }
    return JobLocationSelection(
      position: position,
      exactAddress: resolved == null || resolved.exactAddress.isEmpty
          ? query
          : resolved.exactAddress,
      areaLabel: resolved == null || resolved.areaLabel.isEmpty
          ? 'Pinned service area'
          : resolved.areaLabel,
    );
  }

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
