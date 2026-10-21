import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/client/presentation/screens/post_request_screen.dart';

void main() {
  const categories = [
    'Household Services',
    'Tutoring',
    'Handyman and Repair',
    'Delivery',
    'House Cleaning',
    'Salon Services',
  ];

  test('dashboard category names resolve to admin service names', () {
    expect(
      resolvePostCategory(categories, 'Home Services'),
      'Household Services',
    );
    expect(resolvePostCategory(categories, 'Academic Help'), 'Tutoring');
    expect(resolvePostCategory(categories, 'Repairs'), 'Handyman and Repair');
    expect(resolvePostCategory(categories, 'Errands'), 'Delivery');
    expect(resolvePostCategory(categories, 'Cleaning'), 'House Cleaning');
    expect(resolvePostCategory(categories, 'Beauty'), 'Salon Services');
  });

  test('an exact admin category match is preserved', () {
    expect(resolvePostCategory(categories, 'Delivery'), 'Delivery');
    expect(resolvePostCategory(categories, null), isNull);
  });
}
