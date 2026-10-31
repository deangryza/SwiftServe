import '../models/job_location.dart';
import 'job_location_utils.dart';

/// Absorbs small GPS/geocoder variations without comparing rounded public areas.
const errandSameLocationToleranceMeters = 20.0;
const errandSameLocationMessage =
    'Pickup and drop-off locations must be different for an errand.';

String? validateErrandLocations(
  JobLocationSelection? pickup,
  JobLocationSelection? dropoff,
) {
  if (pickup == null) return 'Choose the pickup point on the map.';
  if (dropoff == null) return 'Choose the drop-off point on the map.';
  if (pickup.exactAddress.trim().isEmpty) return 'Enter the pickup address.';
  if (dropoff.exactAddress.trim().isEmpty) return 'Enter the drop-off address.';
  bool valid(JobCoordinate point) =>
      point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude.abs() <= 90 &&
      point.longitude.abs() <= 180;
  if (!valid(pickup.position) || !valid(dropoff.position)) {
    return 'Choose valid pickup and drop-off points on the map.';
  }
  if (distanceMetersBetween(pickup.position, dropoff.position) <=
      errandSameLocationToleranceMeters) {
    return errandSameLocationMessage;
  }
  return null;
}
