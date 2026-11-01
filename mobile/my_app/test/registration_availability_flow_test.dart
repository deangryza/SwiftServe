import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/screens/client_register_screen.dart';
import 'package:my_app/features/auth/presentation/screens/worker_register_screen.dart';

Future<bool> _lookup(String kind, String value) async =>
    kind == 'email' ? value != 'used@example.com' : value != '+639171234567';

void main() {
  for (final worker in [false, true]) {
    testWidgets(
      '${worker ? 'worker' : 'client'} validates on leaving a field, not while filling earlier fields',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: worker
                ? const WorkerRegisterScreen(contactAvailability: _lookup)
                : const ClientRegisterScreen(contactAvailability: _lookup),
          ),
        );
        await tester.pumpAndSettle();
        final firstName = find.byType(TextFormField).at(0);
        await tester.enterText(firstName, 'Alex');
        await tester.pump();
        expect(find.text('This field is required.'), findsNothing);
        await tester.enterText(find.byType(TextFormField).at(1), 'User');
        final next = find.byKey(
          ValueKey('${worker ? 'worker' : 'client'}-registration-next'),
        );
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        final prefix = worker ? 'worker-' : '';
        final email = find.byKey(ValueKey('${prefix}Email Address'));
        final phone = find.byKey(ValueKey('${prefix}Phone Number'));
        await tester.ensureVisible(email);
        await tester.enterText(email, 'alex@');
        await tester.pump(const Duration(milliseconds: 700));
        expect(find.text('Enter a valid email address.'), findsNothing);
        expect(find.text('Phone number is required.'), findsNothing);
        expect(find.text('Barangay is required.'), findsNothing);
        await tester.ensureVisible(phone);
        await tester.tap(phone);
        await tester.pump();
        expect(find.text('Enter a valid email address.'), findsOneWidget);
        expect(find.text('Phone number is required.'), findsNothing);
        expect(find.text('Province is required.'), findsNothing);
        // Correcting a field clears its error after leaving it.
        await tester.ensureVisible(email);
        await tester.enterText(email, 'alex@example.com');
        await tester.pumpAndSettle();
        await tester.ensureVisible(phone);
        await tester.pumpAndSettle();
        await tester.tap(phone);
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();
        expect(find.text('Enter a valid email address.'), findsNothing);
        // Explicit submission must still validate all required fields.
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(find.text('Phone number is required.'), findsOneWidget);
        expect(find.text('Barangay is required.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${worker ? 'worker' : 'client'} cannot continue with duplicate contacts and can correct them',
      (tester) async {
        tester.view.physicalSize = const Size(364, 1024);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: worker
                ? const WorkerRegisterScreen(contactAvailability: _lookup)
                : const ClientRegisterScreen(contactAvailability: _lookup),
          ),
        );
        await tester.pumpAndSettle();
        final next = find.byKey(
          ValueKey('${worker ? 'worker' : 'client'}-registration-next'),
        );
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(find.text('This field is required.'), findsWidgets);
        final first = tester.element(find.byType(TextFormField).first);
        final errorBorder =
            Theme.of(first).inputDecorationTheme.errorBorder!
                as OutlineInputBorder;
        expect(errorBorder.borderSide.color, const Color(0xFFC62828));
        await tester.enterText(find.byType(TextFormField).at(0), 'Alex');
        await tester.enterText(find.byType(TextFormField).at(1), 'User');
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        final prefix = worker ? 'worker-' : '';
        for (final entry in {
          '${prefix}Email Address': 'used@example.com',
          '${prefix}Phone Number': '9171234567',
          'Barangay': 'Ligas',
          'City / Municipality': 'Malolos',
          'Province': 'Bulacan',
          '${prefix}Password': 'password',
          '${prefix}Confirm Password': 'password',
        }.entries) {
          final field = find.byKey(ValueKey(entry.key));
          await tester.ensureVisible(field);
          await tester.enterText(field, entry.value);
          await tester.pump();
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('policy-consent-checkbox')),
        );
        await tester.tap(find.byKey(const ValueKey('policy-consent-checkbox')));
        await tester.pumpAndSettle();
        expect(
          find.text('This email address is already in use.'),
          findsOneWidget,
        );
        expect(
          find.text('This phone number is already in use.'),
          findsOneWidget,
        );
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('${prefix}Email Address')), findsOneWidget);
        for (final entry in {
          '${prefix}Email Address': 'new@example.com',
          '${prefix}Phone Number': '9177654321',
        }.entries) {
          final field = find.byKey(ValueKey(entry.key));
          await tester.ensureVisible(field);
          await tester.enterText(field, entry.value);
        }
        await tester.pumpAndSettle();
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(
          find.text(worker ? 'Service Categories' : 'Enter code'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
