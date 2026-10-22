import '../models/job_location.dart';
import 'job_location_utils.dart';

// Straight-line distance undercounts real roads, so it is scaled up.
const double errandRoadFactor = 1.3;
const double errandBaseFee = 50;
const double errandPerKmFee = 10;
const double errandFeeStep = 5;

/// Estimated road distance in km between pickup and drop-off.
double errandDistanceKm(JobCoordinate pickup, JobCoordinate dropoff) =>
    distanceMetersBetween(pickup, dropoff) / 1000 * errandRoadFactor;

/// Delivery fee in pesos: base + per-km, rounded up to the nearest ₱5.
double errandDeliveryFee(double distanceKm) {
  final raw = errandBaseFee + errandPerKmFee * distanceKm;
  return (raw / errandFeeStep).ceil() * errandFeeStep;
}
