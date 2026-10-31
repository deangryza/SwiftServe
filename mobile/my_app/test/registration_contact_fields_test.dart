import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/shared/services/api_service.dart';
import 'package:my_app/features/auth/presentation/widgets/registration_contact_fields.dart';
import 'package:my_app/features/auth/presentation/widgets/registration_validation_theme.dart';

void main() {
  Future<
    (
      TextEditingController,
      TextEditingController,
      GlobalKey<RegistrationContactFieldsState>,
    )
  >
  mount(
    WidgetTester tester,
    ContactAvailabilityLookup lookup, {
    bool federated = false,
  }) async {
    final email = TextEditingController(), phone = TextEditingController();
    addTearDown(email.dispose);
    addTearDown(phone.dispose);
    final key = GlobalKey<RegistrationContactFieldsState>();
    await tester.pumpWidget(
      MaterialApp(
        home: RegistrationValidationTheme(
          child: Scaffold(
            body: SingleChildScrollView(
              child: Form(
                child: RegistrationContactFields(
                  key: key,
                  email: email,
                  phone: phone,
                  dialCode: '+63',
                  onDialCodeChanged: (_) {},
                  enabled: true,
                  fieldColor: Colors.white,
                  textColor: Colors.black,
                  mutedColor: Colors.grey,
                  borderColor: Colors.grey,
                  focusColor: Colors.amber,
                  lookup: lookup,
                  federatedAccount: federated,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return (email, phone, key);
  }

  testWidgets(
    'debounces typing and displays duplicate contact errors in red outlined fields',
    (tester) async {
      final requests = <String>[];
      final (email, phone, _) = await mount(tester, (kind, value) async {
        requests.add('$kind:$value');
        return false;
      });
      email.text = 'old@example.com';
      await tester.pump(const Duration(milliseconds: 400));
      email.text = 'used@example.com';
      phone.text = '9171234567';
      await tester.pump(const Duration(milliseconds: 649));
      expect(requests, isEmpty);
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();
      expect(requests, ['email:used@example.com', 'phone:+639171234567']);
      expect(
        find.text('This email address is already in use.'),
        findsOneWidget,
      );
      expect(find.text('This phone number is already in use.'), findsOneWidget);
      final field = tester.element(find.byKey(const ValueKey('Email Address')));
      final decoration = Theme.of(field).inputDecorationTheme;
      expect(
        (decoration.errorBorder! as OutlineInputBorder).borderSide.color,
        const Color(0xFFC62828),
      );
      expect(
        (decoration.focusedErrorBorder! as OutlineInputBorder).borderSide.color,
        const Color(0xFFC62828),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'stale duplicate response cannot overwrite a newer available email',
    (tester) async {
      final old = Completer<bool>();
      final (email, _, _) = await mount(
        tester,
        (_, value) =>
            value == 'old@example.com' ? old.future : Future.value(true),
      );
      email.text = 'old@example.com';
      await tester.pump(const Duration(milliseconds: 651));
      email.text = 'new@example.com';
      await tester.pump(const Duration(milliseconds: 651));
      await tester.pump();
      old.complete(false);
      await tester.pump();
      expect(find.text('This email address is already in use.'), findsNothing);
      expect(find.text('Email is available.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Next flushes debounce and requires current availability; errors can be retried',
    (tester) async {
      var fail = true;
      final (email, phone, key) = await mount(tester, (_, _) async {
        if (fail) throw Exception('offline');
        return true;
      });
      email.text = 'new@example.com';
      phone.text = '9171234567';
      final first = key.currentState!.checkAvailability();
      await tester.pump();
      expect(await first, isFalse);
      expect(
        find.textContaining('Could not verify availability.'),
        findsNWidgets(2),
      );
      fail = false;
      final retry = key.currentState!.checkAvailability();
      await tester.pump();
      expect(await retry, isTrue);
      expect(
        find.textContaining('Could not verify availability.'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Google setup skips its existing read-only email and still checks phone',
    (tester) async {
      final kinds = <String>[];
      final (email, phone, key) = await mount(tester, (kind, _) async {
        kinds.add(kind);
        return true;
      }, federated: true);
      email.text = 'google@example.com';
      phone.text = '9171234567';
      final check = key.currentState!.checkAvailability();
      await tester.pump();
      expect(await check, isTrue);
      expect(kinds, ['phone']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'availability API uses POST and optional authenticated ownership, with strict response validation',
    () async {
      final api = ApiService(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/users/registration-availability');
          expect(request.headers['Authorization'], 'Bearer token');
          expect(jsonDecode(request.body), {
            'kind': 'phone',
            'value': '+639171234567',
          });
          return http.Response('{"available":false}', 200);
        }),
      );
      expect(
        await api.registrationContactAvailable(
          'phone',
          '+639171234567',
          idToken: 'token',
        ),
        isFalse,
      );
      final invalid = ApiService(
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(
        invalid.registrationContactAvailable('email', 'new@example.com'),
        throwsA(isA<ApiConnectionException>()),
      );
    },
  );
}
