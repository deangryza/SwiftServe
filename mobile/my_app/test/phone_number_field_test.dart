import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/widgets/phone_number_field.dart';

void main() {
  test('normalizes Philippine numbers to E.164 format', () {
    expect(normalizePhoneNumber('+63', '0917 123 4567'), '+639171234567');
    expect(normalizePhoneNumber('+63', '9171234567'), '+639171234567');
  });

  test('validates the selected country phone length', () {
    expect(validatePhoneNumber('09171234567', '+63'), isNull);
    expect(validatePhoneNumber('12345', '+63'), isNotNull);
    expect(validatePhoneNumber('2025550123', '+1'), isNull);
    expect(validatePhoneNumber('20255501', '+1'), isNotNull);
  });

  test('Philippine mobile numbers must start with 9', () {
    expect(validatePhoneNumber('8171234567', '+63'), isNotNull);
  });

  testWidgets('Philippine input stops at ten national digits', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            child: PhoneNumberField(
              controller: controller,
              dialCode: '+63',
              onDialCodeChanged: (_) {},
              enabled: true,
              fieldColor: Colors.white,
              textColor: Colors.black,
              mutedColor: Colors.grey,
              borderColor: Colors.grey,
              focusColor: Colors.amber,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), '091712345678999');

    expect(controller.text, '9171234567');
  });
}
