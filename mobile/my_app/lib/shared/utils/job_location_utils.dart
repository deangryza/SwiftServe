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

/// A road leg as "2.1 km · 6 min". Approximate legs run between public area
/// points, so they are prefixed with "~".
String formatRouteLeg(
  double meters,
  double seconds, {
  bool approximate = false,
}) {
  final distance = meters < 1000
      ? '${(meters / 10).round() * 10} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';
  final minutes = math.max(1, (seconds / 60).round());
  final time = minutes < 60
      ? '$minutes min'
      : '${minutes ~/ 60} h ${minutes % 60} min';
  return approximate ? '~$distance · ~$time' : '$distance · $time';
}

double _radians(double degrees) => degrees * math.pi / 180;
