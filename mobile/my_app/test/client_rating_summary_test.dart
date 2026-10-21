import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/widgets/client_rating_summary.dart';

void main() {
  test('calculates the client average from valid worker ratings', () {
    final summary = calculateClientRating([5, 4, 3]);

    expect(summary.average, 4);
    expect(summary.reviewCount, 3);
    expect(summary.displayAverage, '4.0');
  });

  test('ignores missing and out-of-range client ratings', () {
    final summary = calculateClientRating([null, 0, 5, 6, '4']);

    expect(summary.average, 5);
    expect(summary.reviewCount, 1);
  });

  test('shows an empty rating when the client has no reviews', () {
    final summary = calculateClientRating(const []);

    expect(summary.displayAverage, '—');
    expect(summary.reviewCount, 0);
  });
}
