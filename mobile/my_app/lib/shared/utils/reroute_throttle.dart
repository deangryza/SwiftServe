import '../models/job_location.dart';
import 'job_location_utils.dart';

/// Decides when a moving rider's route is worth looking up again.
///
/// Every GPS fix moves the rider marker, but the road route is only fetched
/// again once the rider has moved [minDistanceMeters] and at least
/// [minInterval] has passed. That keeps a 30-minute errand to a few dozen
/// route lookups, inside the routing provider's free quota and the
/// backend's per-user rate limit.
class RerouteThrottle {
  RerouteThrottle({
    this.minDistanceMeters = 100,
    this.minInterval = const Duration(seconds: 20),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final double minDistanceMeters;
  final Duration minInterval;
  final DateTime Function() _clock;

  JobCoordinate? _origin;
  DateTime? _routedAt;

  /// The point the route should start from for the rider's [current]
  /// position: the last routed point until the rider has moved far enough.
  JobCoordinate? update(JobCoordinate? current) {
    if (current == null) return _origin;
    final origin = _origin;
    final routedAt = _routedAt;
    final now = _clock();
    if (origin == null ||
        routedAt == null ||
        (distanceMetersBetween(origin, current) >= minDistanceMeters &&
            now.difference(routedAt) >= minInterval)) {
      _origin = current;
      _routedAt = now;
    }
    return _origin;
  }
}
