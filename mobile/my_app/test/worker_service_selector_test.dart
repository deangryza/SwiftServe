import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/shared/models/worker_service_selection.dart';
import 'package:my_app/shared/services/api_service.dart';
import 'package:my_app/shared/services/profile_draft_store.dart';
import 'package:my_app/shared/screens/public_profile_screen.dart';
import 'package:my_app/features/auth/presentation/widgets/worker_service_selector.dart';

void main() {
  test(
    'legacy category casing can be removed without a duplicate masking the save',
    () {
      final selection = WorkerServiceSelection();
      addTearDown(selection.dispose);
      selection.loadServices(['repairs', 'Pet grooming']);
      expect(selection.contains('Repairs'), isTrue);
      selection.toggle('Repairs');
      expect(selection.services, ['Pet grooming']);
      selection.toggle(' REPAIRS ');
      expect(selection.services, ['Pet grooming', 'REPAIRS']);
      selection.toggle('repairs');
      expect(selection.services, ['Pet grooming']);
    },
  );

  test('edit validation matches backend service count and length limits', () {
    final selection = WorkerServiceSelection();
    addTearDown(selection.dispose);
    selection.loadServices(List.generate(51, (index) => 'Service $index'));
    expect(selection.validationError, 'Select up to 50 services.');
    selection.loadServices(['x' * 81]);
    expect(selection.validationError, contains('80 characters'));
  });

  testWidgets(
    'compact edit categories have no icons and update existing selections',
    (tester) async {
      final selection = WorkerServiceSelection()
        ..loadServices(['repairs', 'Pet grooming']);
      addTearDown(selection.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkerServiceSelector(
              selection: selection,
              categories: const [
                'Repairs',
                'repairs',
                'Beauty',
                'Pet grooming',
              ],
              compact: true,
            ),
          ),
        ),
      );
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(Icon), findsNothing);
      expect(find.byType(FilterChip), findsNWidgets(4));
      final repairs = find.byKey(const ValueKey('worker-category-Repairs'));
      expect(tester.widget<FilterChip>(repairs).selected, isTrue);
      expect(tester.getSize(repairs).height, lessThan(64));
      await tester.tap(repairs);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('worker-category-Beauty')));
      await tester.pump();
      expect(selection.services, ['Pet grooming', 'Beauty']);
      await tester.tap(find.byKey(const ValueKey('worker-category-Other')));
      await tester.pump();
      expect(selection.validationError, 'Please specify your service.');
      await tester.enterText(
        find.byKey(const ValueKey('worker-custom-service')),
        'Gardening',
      );
      expect(selection.services, ['Pet grooming', 'Beauty', 'Gardening']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registration shows the six reference cards and full-width Others below',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final selection = WorkerServiceSelection();
      addTearDown(selection.dispose);
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Form(
                  key: form,
                  child: WorkerServiceSelector(
                    selection: selection,
                    categories: const ['Electrical'],
                    referenceLayout: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final cards = [
        for (final label in registrationServiceCategories)
          find.byKey(ValueKey('worker-category-$label')),
      ];
      for (final card in cards) {
        expect(card, findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey('worker-category-Electrical')),
        findsNothing,
      );
      final other = find.byKey(const ValueKey('worker-category-Other'));
      final first = tester.getRect(cards.first);
      final second = tester.getRect(cards[1]);
      final otherRect = tester.getRect(other);
      expect(first.top, second.top);
      expect(otherRect.width, greaterThan(first.width * 1.9));
      expect(otherRect.top, greaterThan(tester.getRect(cards.last).bottom));
      expect(find.text('Others'), findsOneWidget);
      await tester.tap(cards.first);
      await tester.tap(cards.last);
      await tester.tap(other);
      await tester.pump();
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('worker-custom-service')),
        'Pet grooming',
      );
      expect(form.currentState!.validate(), isTrue);
      expect(selection.services, ['Academic Help', 'Repairs', 'Pet grooming']);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'editing loads existing services and preserves removable custom names',
    () {
      final selection = WorkerServiceSelection();
      addTearDown(selection.dispose);
      selection.loadServices(['Electrical', 'Pet grooming', 'electrical']);
      expect(selection.services, ['Electrical', 'Pet grooming']);
      selection.toggle('Electrical');
      selection.toggle('Repair');
      selection.toggle('Other');
      expect(selection.validationError, isNotNull);
      selection.specifyOther('Gardening');
      expect(selection.services, ['Pet grooming', 'Repair', 'Gardening']);
      selection.toggle('Pet grooming');
      expect(selection.services, ['Repair', 'Gardening']);
    },
  );

  test(
    'multiple services and a specified Other survive draft and registration payload',
    () async {
      final selection = WorkerServiceSelection();
      addTearDown(selection.dispose);
      expect(selection.validationError, isNotNull);
      selection.toggle('Electrical');
      selection.toggle('Other');
      expect(selection.validationError, 'Please specify your service.');
      selection.specifyOther('   ');
      expect(selection.validationError, isNotNull);
      selection.specifyOther('Other');
      expect(selection.validationError, isNotNull);
      selection.specifyOther('  Pet grooming  ');
      selection.toggle('Repair');
      expect(selection.validationError, isNull);
      expect(selection.services, ['Electrical', 'Pet grooming', 'Repair']);
      final draft = ProfileDraft.fromJson(
        ProfileDraft(
          fullName: 'Worker',
          email: 'worker@example.com',
          phoneNumber: '+639171234567',
          address: 'Brgy. Ligas, Malolos, Bulacan',
          role: 'worker',
          category: selection.services.first,
          skills: selection.services,
        ).toJson(),
      );
      expect(profileSkills(draft.skills), selection.services);
      final api = ApiService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['skills'], selection.services);
          expect(body['category'], 'Electrical');
          return http.Response('{}', 201);
        }),
      );
      await api.createUserProfile(
        idToken: 'token',
        fullName: draft.fullName,
        email: draft.email,
        phoneNumber: draft.phoneNumber,
        address: draft.address,
        role: draft.role,
        category: draft.category,
        skills: draft.skills,
      );
      selection.toggle('Other');
      expect(selection.services, ['Electrical', 'Repair']);
    },
  );

  test(
    'custom duplicates are suppressed and deselecting services preserves the others',
    () {
      final selection = WorkerServiceSelection();
      addTearDown(selection.dispose);
      selection.toggle('Repair');
      selection.toggle('Other');
      selection.specifyOther('repair');
      expect(selection.services, ['Repair']);
      selection.toggle('Repair');
      expect(selection.services, ['repair']);
      selection.toggle('Other');
      expect(selection.validationError, isNotNull);
    },
  );

  testWidgets(
    'cards allow multiple selections and require a custom service on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final selection = WorkerServiceSelection();
      addTearDown(selection.dispose);
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Form(
                key: key,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: WorkerServiceSelector(
                    selection: selection,
                    categories: const ['Electrical', 'Repair'],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (final category in ['Electrical', 'Repair', 'Other']) {
        await tester.tap(find.byKey(ValueKey('worker-category-$category')));
        await tester.pump();
      }
      expect(selection.contains('Electrical'), isTrue);
      expect(selection.contains('Repair'), isTrue);
      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('worker-custom-service')),
        'Pet grooming',
      );
      expect(key.currentState!.validate(), isTrue);
      expect(selection.services, ['Electrical', 'Repair', 'Pet grooming']);
      expect(tester.takeException(), isNull);
    },
  );
}
