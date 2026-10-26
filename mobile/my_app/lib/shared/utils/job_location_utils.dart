import 'dart:math' as math;

import '../models/job_location.dart';

const double _earthRadiusMeters = 6371000;

/// How far a public area point can sit from the real pin. Rounding to two
/// decimals moves a point up to ~770 m, so the shown area covers that.
const double publicAreaRadiusMeters = 800;

JobCoordinate roundToPublicArea(JobCoordinate coordinate) => JobCoordinate(
  latitude: _roundToTwoDecimals(coordinate.latitude),
  longitude: _roundToTwoDecimals(coordinate.longitude),
);

double _roundToTwoDecimals(double value) => (value * 100).round() / 100;

double distanceMetersBetween(JobCoordinate from, JobCoordinate to) {
  final latitudeDelta = _radians(to.latitude - from.latitude);
  final longitudeDelta = _radians(to.longitude - from.longitude);
  final fromLatitude = _radians(from.latitude);
  final toLatitude = _radians(to.latitude);
  final a =
      math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(fromLatitude) *
          math.cos(toLatitude) *
          math.sin(longitudeDelta / 2) *
          math.sin(longitudeDelta / 2);
  final angularDistance = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return _earthRadiusMeters * angularDistance;
}

/// Approximate distances are measured to a public area point, which can be
/// up to [publicAreaRadiusMeters] off, so they are kept coarse on purpose.
String formatDistance(double meters, {bool approximate = false}) {
  if (approximate) {
    if (meters < 1000) return 'Under 1 km away';
    final halfKilometers = (meters / 500).round() / 2;
    final label = halfKilometers == halfKilometers.roundToDouble()
        ? halfKilometers.toStringAsFixed(0)
        : halfKilometers.toStringAsFixed(1);
    return '~$label km away';
  }
  if (meters < 1000) {
    final roundedMeters = (meters / 10).round() * 10;
    return '$roundedMeters m away';
  }
  return '${(meters / 1000).toStringAsFixed(1)} km away';
}

double _radians(double degrees) => degrees * math.pi / 180;
