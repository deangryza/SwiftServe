import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/screens/client_account_form.dart';
import 'package:my_app/features/auth/presentation/screens/worker_account_form.dart';
import 'package:my_app/features/auth/presentation/widgets/use_current_location_button.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/services/device_location_service.dart';
import 'package:my_app/shared/services/job_geocoding_service.dart';

const coordinate = JobCoordinate(latitude: 14.84, longitude: 120.81);
const resolved = ResolvedJobAddress(
  exactAddress: '123 Example Street, Malolos, Bulacan',
  areaLabel: 'Malolos, Bulacan',
);

class _Location extends DeviceLocationService {
  int calls = 0;
  DeviceLocationFailure? failure;
  Future<JobCoordinate>? response;
  DeviceLocationFailure? openedSettings;

  @override
  Future<JobCoordinate> currentPosition() async {
    calls++;
    if (failure != null) throw DeviceLocationException(failure!);
    return response ?? Future.value(coordinate);
  }

  @override
  Future<bool> openRecoverySettings(DeviceLocationFailure failure) async {
    openedSettings = failure;
    return true;
  }
}

class _Address extends Fake implements JobAddressResolver {
  int calls = 0;
  bool fail = false;
  Future<ResolvedJobAddress>? response;

  @override
  Future<ResolvedJobAddress> resolve(JobCoordinate position) async {
    calls++;
    expect(position, same(coordinate));
    if (fail) throw StateError('Geocoder offline');
    return response ?? Future.value(resolved);
  }
}

void main() {
  late TextEditingController address;
  late _Location location;
  late _Address resolver;

  setUp(() {
    address = TextEditingController(text: 'Manually entered address');
    location = _Location();
    resolver = _Address();
  });
  tearDown(() => address.dispose());

  Future<void> pumpSubject(WidgetTester tester, {bool enabled = true}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(controller: address),
                UseCurrentLocationButton(
                  address: address,
                  enabled: enabled,
                  locationService: location,
                  addressResolver: resolver,
                ),
              ],
            ),
          ),
        ),
      );

  testWidgets('GPS is opt-in and fills the editable address after tapping', (
    tester,
  ) async {
    await pumpSubject(tester);
    expect(location.calls, 0);
    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();
    expect(location.calls, 1);
    expect(address.text, resolved.exactAddress);
    expect(
      find.text('Address filled. You can edit it before continuing.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'Updated house number');
    expect(address.text, 'Updated house number');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final failure in [
    DeviceLocationFailure.permissionDenied,
    DeviceLocationFailure.permissionPermanentlyDenied,
    DeviceLocationFailure.serviceDisabled,
  ]) {
    testWidgets('$failure preserves manual input and offers recovery', (
      tester,
    ) async {
      location.failure = failure;
      await pumpSubject(tester);
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
      expect(address.text, 'Manually entered address');
      expect(resolver.calls, 0);
      expect(find.textContaining('manually'), findsOneWidget);
      if (failure != DeviceLocationFailure.permissionDenied) {
        await tester.tap(find.text('Open settings'));
        await tester.pumpAndSettle();
        expect(location.openedSettings, failure);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('reverse-geocoding failure preserves the existing address', (
    tester,
  ) async {
    resolver.fail = true;
    await pumpSubject(tester);
    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();
    expect(address.text, 'Manually entered address');
    expect(find.textContaining('Could not find your address'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('manual editing while GPS starts prevents an overwrite', (
    tester,
  ) async {
    final pending = Completer<JobCoordinate>();
    location.response = pending.future;
    await pumpSubject(tester);
    await tester.tap(find.text('Use my current location'));
    await tester.pump();
    expect(find.text('Finding address…'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'A newer address');
    pending.complete(coordinate);
    await tester.pumpAndSettle();
    expect(address.text, 'A newer address');
    expect(resolver.calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'late address lookup cannot overwrite manual edits or a disposed form',
    (tester) async {
      final pending = Completer<ResolvedJobAddress>();
      resolver.response = pending.future;
      await pumpSubject(tester);
      await tester.tap(find.text('Use my current location'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Keep this address');
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(resolved);
      await tester.pump();
      expect(address.text, 'Keep this address');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled registration does not request location', (
    tester,
  ) async {
    await pumpSubject(tester, enabled: false);
    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.onPressed, isNull);
    expect(location.calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final worker in [false, true]) {
    for (final google in [false, true]) {
      testWidgets(
        '${worker ? 'worker' : 'client'} ${google ? 'Google' : 'email'} form exposes the same location action',
        (tester) async {
          final name = TextEditingController(text: 'Alex Example');
          final email = TextEditingController();
          final phone = TextEditingController();
          final password = TextEditingController();
          final confirmation = TextEditingController();
          final category = TextEditingController();
          final key = GlobalKey<FormState>();
          final form = worker
              ? WorkerAccountForm(
                  formKey: key,
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
                  federatedAccount: google,
                )
              : ClientAccountForm(
                  formKey: key,
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
                  federatedAccount: google,
                );
          await tester.pumpWidget(MaterialApp(home: form));
          await tester.ensureVisible(find.text('Next'));
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
          final action = tester.widget<UseCurrentLocationButton>(
            find.byType(UseCurrentLocationButton),
          );
          expect(action.address, same(address));
          expect(action.enabled, isTrue);
          expect(find.byKey(const ValueKey('Barangay')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('City / Municipality')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('Province')), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          for (final controller in [
            name,
            email,
            phone,
            password,
            confirmation,
            category,
          ]) {
            controller.dispose();
          }
        },
      );
    }
  }
}
