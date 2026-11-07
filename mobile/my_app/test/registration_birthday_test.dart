import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/shared/services/api_service.dart';
import 'package:my_app/shared/services/profile_draft_store.dart';
import 'package:my_app/shared/utils/registration_birthday.dart';
import 'package:my_app/features/auth/presentation/widgets/registration_birthday_field.dart';
import 'package:my_app/features/auth/presentation/screens/client_register_screen.dart';
import 'package:my_app/features/auth/presentation/screens/worker_register_screen.dart';

void main() {
  for (final worker in [false, true]) {
    testWidgets(
      '${worker ? 'worker' : 'client'} cannot advance without an adult birthday',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: worker
                ? const WorkerRegisterScreen()
                : const ClientRegisterScreen(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).at(0), 'Synthetic');
        await tester.enterText(find.byType(TextFormField).at(1), 'User');
        final next = find.byKey(
          ValueKey('${worker ? 'worker' : 'client'}-registration-next'),
        );
        Future<void> advance() async {
          await tester.ensureVisible(next);
          await tester.pumpAndSettle();
          await tester.tap(next);
          await tester.pumpAndSettle();
        }

        await advance();
        expect(find.byType(RegistrationBirthdayField), findsOneWidget);
        await advance();
        expect(find.text('Birthday is required.'), findsOneWidget);
        final birthday = tester.widget<RegistrationBirthdayField>(
          find.byType(RegistrationBirthdayField),
        );
        birthday.controller.text = RegistrationBirthday.encode(
          RegistrationBirthday.today(),
        );
        await advance();
        expect(
          find.text(RegistrationBirthday.ineligibleMessage),
          findsOneWidget,
        );
        expect(find.text('First Name'), findsNothing);
        expect(find.byKey(const ValueKey('Barangay')), findsOneWidget);
        for (final entry in {
          'Barangay': 'Ligas',
          'City / Municipality': 'Malolos',
          'Province': 'Bulacan',
        }.entries) {
          final field = find.byKey(ValueKey(entry.key));
          await tester.ensureVisible(field);
          await tester.enterText(field, entry.value);
        }
        birthday.controller.text = '2000-01-01';
        await advance();
        expect(find.text('Email Address'), findsOneWidget);
        expect(find.text('First Name'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  final now = DateTime.utc(2026, 11, 2, 16); // November 3 in the Philippines.
  test('age uses complete Philippine calendar date, including midnight', () {
    expect(RegistrationBirthday.validate('2008-11-03', now: now), isNull);
    expect(
      RegistrationBirthday.validate('2008-11-04', now: now),
      RegistrationBirthday.ineligibleMessage,
    );
    expect(
      RegistrationBirthday.validate(
        '2008-11-03',
        now: now.subtract(const Duration(seconds: 1)),
      ),
      RegistrationBirthday.ineligibleMessage,
    );
    expect(RegistrationBirthday.validate('2007-12-31', now: now), isNull);
    for (final value in ['', 'bad', '2007-02-29', '2026-11-04']) {
      expect(RegistrationBirthday.validate(value, now: now), isNotNull);
    }
    expect(
      RegistrationBirthday.validate(
        '2008-02-29',
        now: DateTime.utc(2026, 2, 28),
      ),
      RegistrationBirthday.ineligibleMessage,
    );
    expect(
      RegistrationBirthday.validate(
        '2008-02-29',
        now: DateTime.utc(2026, 3, 1),
      ),
      isNull,
    );
  });

  testWidgets(
    'birthday is required, read-only and opens a bounded calendar picker',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: form,
              child: RegistrationBirthdayField(controller: controller),
            ),
          ),
        ),
      );
      expect(form.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('Birthday is required.'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await tester.tap(find.byType(TextFormField));
      await tester.pumpAndSettle();
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.lastDate, RegistrationBirthday.today());
      expect(picker.initialEntryMode, DatePickerEntryMode.calendarOnly);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(RegistrationBirthday.parse(controller.text), isNotNull);
      expect(form.currentState!.validate(), isTrue);
      controller.text = RegistrationBirthday.encode(
        RegistrationBirthday.today(),
      );
      expect(form.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text(RegistrationBirthday.ineligibleMessage), findsOneWidget);
    },
  );

  test(
    'API rejects invalid ages before any request and serializes valid date only',
    () async {
      var requests = 0;
      final api = ApiService(
        client: MockClient((request) async {
          requests++;
          expect(jsonDecode(request.body)['dateOfBirth'], '2000-02-29');
          return http.Response('{}', 201);
        }),
      );
      Future<void> submit(String date) => api.createUserProfile(
        idToken: 'test',
        fullName: 'Adult',
        email: 'adult@example.test',
        phoneNumber: '+639171234567',
        address: 'Brgy. Ligas, Malolos, Bulacan',
        role: 'client',
        dateOfBirth: date,
      );
      for (final value in [
        '',
        RegistrationBirthday.encode(RegistrationBirthday.today()),
      ]) {
        await expectLater(submit(value), throwsArgumentError);
      }
      expect(requests, 0);
      await submit('2000-02-29');
      expect(requests, 1);
      final draft = ProfileDraft(
        fullName: 'Adult',
        email: 'adult@example.test',
        phoneNumber: '',
        address: '',
        role: 'worker',
        dateOfBirth: '2000-02-29',
      );
      expect(ProfileDraft.fromJson(draft.toJson()).dateOfBirth, '2000-02-29');
      expect(
        ProfileDraft.fromJson(
          {...draft.toJson()}..remove('dateOfBirth'),
        ).dateOfBirth,
        '',
      );
    },
  );
}
