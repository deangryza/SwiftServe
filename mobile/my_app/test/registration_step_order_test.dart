import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/screens/client_register_screen.dart';
import 'package:my_app/features/auth/presentation/screens/worker_register_screen.dart';
import 'package:my_app/features/auth/presentation/widgets/registration_birthday_field.dart';
import 'package:my_app/features/auth/presentation/widgets/registration_address_fields.dart';
import 'package:my_app/features/auth/presentation/widgets/use_current_location_button.dart';

void main() {
  for (final worker in [false, true]) {
    for (final width in [320.0, 390.0]) {
      testWidgets(
        '${worker ? 'worker' : 'client'} separates name, personal details and credentials at $width',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          var contactChecks = 0;
          Future<bool> lookup(String kind, String value) async {
            contactChecks++;
            return true;
          }

          await tester.pumpWidget(
            MaterialApp(
              home: worker
                  ? WorkerRegisterScreen(contactAvailability: lookup)
                  : ClientRegisterScreen(contactAvailability: lookup),
            ),
          );
          await tester.pumpAndSettle();
          final next = find.byKey(
            ValueKey('${worker ? 'worker' : 'client'}-registration-next'),
          );
          Future<void> advance() async {
            await tester.ensureVisible(next);
            await tester.pumpAndSettle();
            await tester.tap(next);
            await tester.pumpAndSettle();
          }

          expect(find.byType(TextFormField), findsNWidgets(2));
          expect(find.byType(RegistrationBirthdayField), findsNothing);
          expect(find.byType(RegistrationAddressFields), findsNothing);
          await tester.enterText(find.byType(TextFormField).at(0), 'Alex');
          await tester.enterText(find.byType(TextFormField).at(1), 'User');
          await advance();
          expect(find.byType(RegistrationBirthdayField), findsOneWidget);
          expect(find.byType(RegistrationAddressFields), findsOneWidget);
          expect(find.byType(UseCurrentLocationButton), findsOneWidget);
          expect(find.text('Email Address'), findsNothing);
          expect(find.text('First Name'), findsNothing);
          await advance();
          expect(find.text('Birthday is required.'), findsOneWidget);
          expect(find.text('Barangay is required.'), findsOneWidget);
          tester
                  .widget<RegistrationBirthdayField>(
                    find.byType(RegistrationBirthdayField),
                  )
                  .controller
                  .text =
              '2000-01-01';
          for (final entry in {
            'Barangay': 'Ligas',
            'City / Municipality': 'Malolos',
            'Province': 'Bulacan',
          }.entries) {
            final field = find.byKey(ValueKey(entry.key));
            await tester.ensureVisible(field);
            await tester.enterText(field, entry.value);
          }
          await advance();
          expect(contactChecks, 0);
          expect(find.text('Email Address'), findsOneWidget);
          expect(find.text('Phone Number'), findsOneWidget);
          expect(find.text('Password'), findsOneWidget);
          expect(find.text('Confirm Password'), findsOneWidget);
          expect(find.byType(RegistrationBirthdayField), findsNothing);
          expect(find.byType(RegistrationAddressFields), findsNothing);
          final prefix = worker ? 'worker-' : '';
          final email = find.byKey(ValueKey('${prefix}Email Address'));
          await tester.enterText(email, 'alex@example.test');
          await tester.pumpAndSettle();
          // Android/system Back moves to the preceding wizard page.
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<RegistrationBirthdayField>(
                  find.byType(RegistrationBirthdayField),
                )
                .controller
                .text,
            '2000-01-01',
          );
          expect(find.text('Ligas'), findsOneWidget);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.text('Alex'), findsOneWidget);
          expect(find.text('User'), findsOneWidget);
          await advance();
          await advance();
          expect(find.text('alex@example.test'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
