import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/screens/client_account_form.dart';
import 'package:my_app/features/auth/presentation/screens/worker_account_form.dart';

void main() {
  testWidgets(
    'Google client flow prefills identity and does not ask for a password',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(MaterialApp(home: harness.clientForm()));

      expect(find.text('Google'), findsOneWidget);
      expect(find.text('User'), findsOneWidget);
      await _tapNext(tester, 'client-registration-next');

      expect(find.text('Password'), findsNothing);
      expect(find.text('Confirm Password'), findsNothing);
      final email = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('Email Address')),
          matching: find.byType(TextField),
        ),
      );
      expect(email.readOnly, isTrue);
      expect(email.controller?.text, 'google@example.com');
    },
  );

  testWidgets(
    'Google worker flow prefills identity and does not ask for a password',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(MaterialApp(home: harness.workerForm()));

      await _tapNext(tester, 'worker-registration-next');

      expect(find.text('Password'), findsNothing);
      expect(find.text('Confirm Password'), findsNothing);
      final email = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('worker-Email Address')),
          matching: find.byType(TextField),
        ),
      );
      expect(email.readOnly, isTrue);
      expect(email.controller?.text, 'google@example.com');
    },
  );
}

Future<void> _tapNext(WidgetTester tester, String key) async {
  final button = find.byKey(ValueKey(key));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

class _Harness {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(text: 'Google User');
  final email = TextEditingController(text: 'google@example.com');
  final phone = TextEditingController();
  final address = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  final category = TextEditingController();

  Widget clientForm() => ClientAccountForm(
    formKey: formKey,
    name: name,
    email: email,
    phone: phone,
    address: address,
    password: password,
    confirmPassword: confirmation,
    acceptedTerms: false,
    onTermsChanged: (_) {},
    loading: false,
    profileImage: null,
    onPickImage: () {},
    onRegister: () {},
    federatedAccount: true,
  );

  Widget workerForm() => WorkerAccountForm(
    formKey: formKey,
    name: name,
    email: email,
    phone: phone,
    address: address,
    password: password,
    confirmPassword: confirmation,
    category: category,
    acceptedTerms: false,
    onTermsChanged: (_) {},
    loading: false,
    profileImage: null,
    onPickImage: () {},
    onRegister: () {},
    federatedAccount: true,
  );

  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    address.dispose();
    password.dispose();
    confirmation.dispose();
    category.dispose();
  }
}
