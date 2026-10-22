import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/client/presentation/screens/post_request_screen.dart';
import 'package:my_app/features/client/presentation/widgets/errand_tracking_map.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/models/rider_location.dart';
import 'package:my_app/shared/models/service_request.dart';
import 'package:my_app/shared/utils/errand_pricing.dart';

ServiceRequest _errand(Map<String, dynamic> overrides) =>
    ServiceRequest.fromMap('errand-1', {
      'clientId': 'client-1',
      'title': 'Buy groceries',
      'location': 'Malolos',
      'budget': 99,
      'modality': 'errand',
      'workerName': 'Rider One',
      ...overrides,
    });

void main() {
  test('distance is the straight line scaled for roads', () {
    const pickup = JobCoordinate(latitude: 14.8441, longitude: 120.8119);
    const dropoff = JobCoordinate(latitude: 14.7912, longitude: 120.8811);
    final km = errandDistanceKm(pickup, dropoff);
    // About 9.5 km straight, so about 12.4 km by road.
    expect(km, closeTo(12.4, 0.3));
    expect(errandDistanceKm(pickup, pickup), 0);
  });

  test('fee is base plus per km, rounded up to the nearest 5 pesos', () {
    expect(errandDeliveryFee(0), 50);
    expect(errandDeliveryFee(1), 60);
    expect(errandDeliveryFee(2.3), 75);
    expect(errandDeliveryFee(12.4), 175);
  });

  test('errand categories pick the errand work type', () {
    expect(isErrandCategory('Errands'), isTrue);
    expect(isErrandCategory('Delivery & pickup'), isTrue);
    expect(isErrandCategory('Repairs'), isFalse);
    expect(isErrandCategory(null), isFalse);
  });

  test('stage timeline counts finished steps', () {
    expect(
      ErrandStageTimeline.completedSteps(_errand({'status': 'accepted'})),
      0,
    );
    expect(
      ErrandStageTimeline.completedSteps(
        _errand({'status': 'ongoing', 'errandStage': 'headingToPickup'}),
      ),
      1,
    );
    expect(
      ErrandStageTimeline.completedSteps(
        _errand({'status': 'ongoing', 'errandStage': 'delivering'}),
      ),
      3,
    );
    expect(
      ErrandStageTimeline.completedSteps(_errand({'status': 'completed'})),
      4,
    );
  });

  test('rider status shows live, stale and waiting states', () {
    final now = DateTime(2026, 10, 23, 12);
    final ongoing = _errand({'status': 'ongoing'});
    RiderLocation seenAgo(Duration age) => RiderLocation(
      position: const JobCoordinate(latitude: 14.8, longitude: 120.8),
      updatedAt: now.subtract(age),
    );

    expect(
      riderStatusText(ongoing, null, now),
      "Waiting for Rider One's location…",
    );
    expect(
      riderStatusText(ongoing, seenAgo(const Duration(seconds: 10)), now),
      'Rider One is live on the map.',
    );
    expect(
      riderStatusText(ongoing, seenAgo(const Duration(minutes: 3)), now),
      'Last seen 3 min ago.',
    );
    expect(
      riderStatusText(_errand({'status': 'accepted'}), null, now),
      'Rider One will share their location once they start.',
    );
  });
}
