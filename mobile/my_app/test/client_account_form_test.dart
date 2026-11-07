import 'helpers/registration_steps.dart';
import 'package:my_app/features/auth/presentation/widgets/registration_birthday_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/screens/client_account_form.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    testWidgets('client flow preserves credentials and fits $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controllers = List.generate(6, (_) => TextEditingController());
      addTearDown(() {
        for (final controller in controllers) {
          controller.dispose();
        }
      });
      final formKey = GlobalKey<FormState>();
      bool accepted = false;
      bool submitted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: ClientAccountForm(
                formKey: formKey,
                name: controllers[0],
                email: controllers[1],
                phone: controllers[2],
                address: controllers[3],
                password: controllers[4],
                confirmPassword: controllers[5],
                acceptedTerms: accepted,
                onTermsChanged: (value) => setState(() => accepted = value),
                loading: false,
                profileImage: null,
                onPickImage: () {},
                onRegister: () => submitted = true,
                contactAvailability: (_, _) async => true,
              ),
            ),
          ),
        ),
      );
      Future<void> fill(String label, String text) async {
        final field = find.byKey(ValueKey(label));
        await tester.ensureVisible(field);
        await tester.enterText(field, text);
        await tester.pumpAndSettle();
      }

      Future<void> advance() async {
        fillAdultBirthday(tester);
        final button = find.byKey(const ValueKey('client-registration-next'));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        await completePersonalDetails(tester, button);
        expect(tester.takeException(), isNull);
        expect(find.text('Account'), findsNothing);
        expect(find.text('Verification'), findsNothing);
        expect(find.text('Review'), findsNothing);
        expect(find.text('Credentials'), findsNothing);
      }

      await fill('First Name', 'Jane');
      await fill('Last Name', 'Doe');
      await advance();
      expect(controllers[0].text, 'Jane Doe');
      await fill('Email Address', 'jane@example.com');
      await fill('Phone Number', '09123456789');
      await fill('Password', 'password123');
      await fill('Confirm Password', 'password123');
      await tester.ensureVisible(
        find.byKey(const ValueKey('policy-consent-checkbox')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('policy-consent-checkbox')));
      await tester.pumpAndSettle();
      await advance();
      expect(find.text('Enter One-Time-Password'), findsOneWidget);
      await advance();
      expect(find.text('Front side'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        final skip = find.text('Skip for now');
        await tester.ensureVisible(skip);
        await tester.pumpAndSettle();
        await tester.tap(skip);
        await tester.pumpAndSettle();
        if (i == 0) {
          // Skipping ID must offer a way back instead of a dead selfie button.
          final addId = find.text('Add ID photos first');
          await tester.ensureVisible(addId);
          await tester.pumpAndSettle();
          await tester.tap(addId);
          await tester.pumpAndSettle();
          expect(find.text('Front side'), findsOneWidget);
          final skipAgain = find.text('Skip for now');
          await tester.ensureVisible(skipAgain);
          await tester.pumpAndSettle();
          await tester.tap(skipAgain);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Verification after registration'), findsOneWidget);
      expect(submitted, isFalse);
      await advance();
      expect(submitted, isTrue);
      expect(controllers[1].text, 'jane@example.com');
      expect(controllers[4].text, 'password123');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

void fillAdultBirthday(WidgetTester tester) {
  for (final field in tester.widgetList<RegistrationBirthdayField>(
    find.byType(RegistrationBirthdayField),
  )) {
    if (field.controller.text.isEmpty) field.controller.text = '2000-01-01';
  }
}
