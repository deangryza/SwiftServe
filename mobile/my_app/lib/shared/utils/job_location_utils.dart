import 'dart:math' as math;

import '../models/job_location.dart';

const double _earthRadiusMeters = 6371000;

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
  final a = math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(fromLatitude) *
          math.cos(toLatitude) *
          math.sin(longitudeDelta / 2) *
          math.sin(longitudeDelta / 2);
  final angularDistance = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return _earthRadiusMeters * angularDistance;
}

String formatDistance(double meters, {bool approximate = false}) {
  final prefix = approximate ? '~' : '';
  if (meters < 1000) {
    final roundedMeters = (meters / 10).round() * 10;
    return '$prefix$roundedMeters m away';
  }
  return '$prefix${(meters / 1000).toStringAsFixed(1)} km away';
}

double _radians(double degrees) => degrees * math.pi / 180;
