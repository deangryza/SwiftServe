import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/widgets/worker_rating_summary.dart';

void main() {
  test('calculates the worker average from valid client ratings', () {
    final summary = calculateWorkerRating([5, 4, 3]);

    expect(summary.average, 4);
    expect(summary.reviewCount, 3);
    expect(summary.displayAverage, '4.0');
  });

  test('ignores missing and out-of-range rating values', () {
    final summary = calculateWorkerRating([null, '5', 0, 6, 4.5]);

    expect(summary.average, 4.5);
    expect(summary.reviewCount, 1);
  });

  test('shows an empty rating when the worker has no reviews', () {
    final summary = calculateWorkerRating(const []);

    expect(summary.reviewCount, 0);
    expect(summary.displayAverage, '—');
  });
}
