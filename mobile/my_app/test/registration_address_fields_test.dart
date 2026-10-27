import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/widgets/registration_address_fields.dart';
import 'package:my_app/features/auth/presentation/widgets/use_current_location_button.dart';
import 'package:my_app/shared/services/job_geocoding_service.dart';

void main() {
  late TextEditingController address;
  late GlobalKey<FormState> form;
  setUp(() {
    address = TextEditingController();
    form = GlobalKey<FormState>();
  });
  tearDown(() => address.dispose());

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Form(
            key: form,
            child: RegistrationAddressFields(
              address: address,
              enabled: true,
              fieldColor: Colors.white,
              textColor: Colors.black,
              mutedColor: Colors.black54,
              borderColor: Colors.grey,
              focusColor: Colors.amber,
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> fill(WidgetTester tester, String label, String text) async {
    final field = find.byKey(ValueKey(label));
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
  }

  testWidgets(
    'editing an existing address requires the cleared component again',
    (tester) async {
      address.text = '123 Example Street, Bulihan, Malolos, Bulacan';
      await pump(tester);
      expect(form.currentState!.validate(), isTrue);
      expect(find.text('Bulihan'), findsOneWidget);
      expect(find.text('Malolos'), findsOneWidget);
      expect(find.text('Bulacan'), findsOneWidget);
      await fill(tester, 'Province', '');
      expect(form.currentState!.validate(), isFalse);
      await fill(tester, 'Province', 'Pampanga');
      expect(form.currentState!.validate(), isTrue);
      expect(address.text, '123 Example Street, Bulihan, Malolos, Pampanga');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'an older incomplete address is retained until edited and can be completed',
    (tester) async {
      address.text = '123 Example Street';
      await pump(tester);
      expect(address.text, '123 Example Street');
      await fill(tester, 'Barangay', 'Bulihan');
      expect(form.currentState!.validate(), isFalse);
      await fill(tester, 'City / Municipality', 'Malolos');
      await fill(tester, 'Province', 'Bulacan');
      expect(form.currentState!.validate(), isTrue);
      expect(address.text, '123 Example Street, Bulihan, Malolos, Bulacan');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final missing in ['Barangay', 'City / Municipality', 'Province']) {
    testWidgets('$missing must be provided, including whitespace-only input', (
      tester,
    ) async {
      await pump(tester);
      for (final entry in {
        'Barangay': 'Bulihan',
        'City / Municipality': 'Malolos',
        'Province': 'Bulacan',
      }.entries) {
        await fill(
          tester,
          entry.key,
          entry.key == missing ? '   ' : entry.value,
        );
      }
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('$missing is required.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'three required components compose the saved address without a street',
    (tester) async {
      await pump(tester);
      await fill(tester, 'Barangay', ' Bulihan ');
      await fill(tester, 'City / Municipality', ' Malolos ');
      await fill(tester, 'Province', ' Bulacan ');
      expect(form.currentState!.validate(), isTrue);
      expect(address.text, 'Bulihan, Malolos, Bulacan');
      await fill(tester, 'Street / House No. (optional)', '123 Example Street');
      expect(address.text, '123 Example Street, Bulihan, Malolos, Bulacan');
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(tester);
      expect(form.currentState!.validate(), isTrue);
      expect(find.text('Bulihan'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('GPS fills structured fields and leaves them editable', (
    tester,
  ) async {
    await pump(tester);
    tester
        .widget<UseCurrentLocationButton>(find.byType(UseCurrentLocationButton))
        .onAddressResolved!(
      const ResolvedJobAddress(
        exactAddress: '123 Example Street, Bulihan, Malolos, Bulacan',
        areaLabel: 'Bulihan, Malolos',
        street: '123 Example Street',
        barangay: 'Bulihan',
        cityMunicipality: 'Malolos',
        province: 'Bulacan',
      ),
    );
    expect(form.currentState!.validate(), isTrue);
    expect(address.text, '123 Example Street, Bulihan, Malolos, Bulacan');
    await fill(tester, 'Barangay', 'Guinhawa');
    expect(address.text, '123 Example Street, Guinhawa, Malolos, Bulacan');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('GPS without a barangay requires manual completion', (
    tester,
  ) async {
    await pump(tester);
    tester
        .widget<UseCurrentLocationButton>(find.byType(UseCurrentLocationButton))
        .onAddressResolved!(
      const ResolvedJobAddress(
        exactAddress: 'Malolos, Bulacan',
        areaLabel: 'Malolos',
        cityMunicipality: 'Malolos',
        province: 'Bulacan',
      ),
    );
    expect(form.currentState!.validate(), isFalse);
    await fill(tester, 'Barangay', 'Bulihan');
    expect(form.currentState!.validate(), isTrue);
    expect(address.text, 'Bulihan, Malolos, Bulacan');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
