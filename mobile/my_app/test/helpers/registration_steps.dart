import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/widgets/registration_birthday_field.dart';

/// Existing credential/service tests use synthetic personal details to reach
/// the step they exercise. Dedicated flow tests check this step itself.
Future<void> completePersonalDetails(WidgetTester tester, Finder next) async {
  final birthday = find.byType(RegistrationBirthdayField);
  if (birthday.evaluate().isEmpty) return;
  tester.widget<RegistrationBirthdayField>(birthday).controller.text =
      '2000-01-01';
  for (final entry in {
    'Street / House No. (optional)': '123 Service Lane',
    'Barangay': 'Bulihan',
    'City / Municipality': 'Malolos',
    'Province': 'Bulacan',
  }.entries) {
    final field = find.byKey(ValueKey(entry.key));
    await tester.ensureVisible(field);
    await tester.enterText(field, entry.value);
  }
  await tester.ensureVisible(next);
  await tester.pumpAndSettle();
  await tester.tap(next);
  await tester.pumpAndSettle();
}
