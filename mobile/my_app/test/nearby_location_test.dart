import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/worker/presentation/widgets/worker_nearby_location_panel.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/services/device_location_service.dart';
import 'package:my_app/shared/services/nearby_location_controller.dart';

class _Device extends DeviceLocationService {
  bool granted = false;
  Object? failure;
  JobCoordinate position = const JobCoordinate(
    latitude: 14.84,
    longitude: 120.81,
  );
  Future<JobCoordinate> Function()? lookup;
  int permissionChecks = 0, calls = 0, active = 0, maxActive = 0, settings = 0;

  @override
  Future<bool> hasPermission() async {
    permissionChecks++;
    if (failure != null) throw failure!;
    return granted;
  }

  @override
  Future<JobCoordinate> currentPosition() async {
    calls++;
    active++;
    maxActive = math.max(maxActive, active);
    try {
      if (failure != null) throw failure!;
      granted = true;
      return lookup == null ? position : await lookup!();
    } finally {
      active--;
    }
  }

  @override
  Future<bool> openRecoverySettings(DeviceLocationFailure failure) async {
    settings++;
    return true;
  }
}

void main() {
  test(
    'recreated dashboards wait for old native GPS and then get a fresh fix',
    () async {
      final oldDevice = _Device()..granted = true;
      final oldFix = Completer<JobCoordinate>();
      oldDevice.lookup = () => oldFix.future;
      final oldScreen = NearbyLocationController(service: oldDevice);
      final pendingOld = oldScreen.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(oldDevice.calls, 1);
      oldScreen.dispose();
      final freshDevice = _Device()..granted = true;
      final reopened = NearbyLocationController(service: freshDevice);
      addTearDown(reopened.dispose);
      final pendingNew = reopened.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(freshDevice.calls, 0);
      oldFix.complete(oldDevice.position);
      await Future.wait([pendingOld, pendingNew]);
      expect(freshDevice.calls, 1);
      expect(oldDevice.active, 0);
      expect(reopened.position, same(freshDevice.position));
    },
  );

  test(
    'ungranted permission needs an explicit action and does not request GPS automatically',
    () async {
      final device = _Device();
      final controller = NearbyLocationController(service: device);
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.permissionRequired, isTrue);
      expect(controller.position, isNull);
      expect(device.calls, 0);
      await controller.refresh(requestPermission: true);
      expect(device.calls, 1);
      expect(controller.position, same(device.position));
    },
  );
  test(
    'granted permission fetches current GPS, refreshing after moving replaces the old center',
    () async {
      final device = _Device()..granted = true;
      final controller = NearbyLocationController(service: device);
      addTearDown(controller.dispose);
      await controller.refresh();
      final previous = controller.position;
      device.position = const JobCoordinate(latitude: 15.84, longitude: 120.81);
      await controller.refresh(requestPermission: true);
      expect(controller.position, same(device.position));
      expect(controller.position, isNot(same(previous)));
      expect(device.calls, 2);
    },
  );
  for (final failure in DeviceLocationFailure.values) {
    test(
      '$failure clears previous coordinates without a home-address fallback',
      () async {
        final device = _Device()..granted = true;
        final controller = NearbyLocationController(service: device);
        addTearDown(controller.dispose);
        await controller.refresh();
        device.failure = DeviceLocationException(failure);
        await controller.refresh(requestPermission: true);
        expect(controller.position, isNull);
        expect(controller.error?.failure, failure);
        expect(controller.loading, isFalse);
      },
    );
  }
  test(
    'invalid GPS coordinates and unexpected platform failures are handled safely',
    () async {
      final device = _Device()
        ..granted = true
        ..position = const JobCoordinate(latitude: double.nan, longitude: 120);
      final controller = NearbyLocationController(service: device);
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.error?.failure, DeviceLocationFailure.unavailable);
      expect(controller.position, isNull);
      device.failure = StateError('platform failure');
      await controller.refresh(requestPermission: true);
      expect(controller.error?.failure, DeviceLocationFailure.unavailable);
    },
  );
  test('rapid refresh calls share one native request', () async {
    final device = _Device()..granted = true;
    final gate = Completer<JobCoordinate>();
    device.lookup = () => gate.future;
    final controller = NearbyLocationController(service: device);
    addTearDown(controller.dispose);
    final first = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    final second = controller.refresh(requestPermission: true);
    expect(device.calls, 1);
    expect(controller.loading, isTrue);
    gate.complete(device.position);
    await Future.wait([first, second]);
    expect(device.maxActive, 1);
  });
  test(
    'leaving and reopening ignores an old fix and queues fresh GPS without overlap',
    () async {
      final device = _Device()..granted = true;
      final old = Completer<JobCoordinate>();
      final fresh = Completer<JobCoordinate>();
      device.lookup = () => device.calls == 1 ? old.future : fresh.future;
      final controller = NearbyLocationController(service: device);
      addTearDown(controller.dispose);
      final first = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      controller.invalidate();
      final reopened = controller.refresh();
      expect(controller.loading, isTrue);
      old.complete(const JobCoordinate(latitude: 1, longitude: 1));
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(controller.position, isNull);
      expect(device.calls, 2);
      fresh.complete(device.position);
      await reopened;
      expect(controller.position, same(device.position));
      expect(device.maxActive, 1);
    },
  );
  test(
    'leaving again cancels a queued refresh and dispose ignores a pending GPS response',
    () async {
      final device = _Device()..granted = true;
      final old = Completer<JobCoordinate>();
      device.lookup = () => old.future;
      final controller = NearbyLocationController(service: device);
      final first = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      controller.invalidate();
      final queued = controller.refresh();
      controller.invalidate();
      old.complete(device.position);
      await Future.wait([first, queued]);
      expect(device.calls, 1);
      expect(controller.position, isNull);
      final next = Completer<JobCoordinate>();
      device.lookup = () => next.future;
      final pending = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      next.complete(device.position);
      await pending;
      expect(controller.position, isNull);
    },
  );
  testWidgets(
    'Nearby explains access, shows loading, and refreshes current coordinates',
    (tester) async {
      final device = _Device();
      final controller = NearbyLocationController(service: device);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkerNearbyLocationPanel(controller: controller),
          ),
        ),
      );
      await controller.refresh();
      await tester.pump();
      expect(
        find.textContaining('Your saved address will stay unchanged'),
        findsOneWidget,
      );
      expect(find.text('Use My Current Location'), findsOneWidget);
      final gate = Completer<JobCoordinate>();
      device.lookup = () => gate.future;
      await tester.tap(find.text('Use My Current Location'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Use My Current Location'), findsNothing);
      gate.complete(device.position);
      await tester.pumpAndSettle();
      expect(find.textContaining('current location'), findsOneWidget);
      expect(find.text('Refresh nearby jobs'), findsOneWidget);
      device.lookup = null;
      device.position = const JobCoordinate(latitude: 15, longitude: 121);
      await tester.tap(find.text('Refresh nearby jobs'));
      await tester.pumpAndSettle();
      expect(controller.position, same(device.position));
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
  for (final failure in [
    DeviceLocationFailure.permissionPermanentlyDenied,
    DeviceLocationFailure.serviceDisabled,
  ]) {
    testWidgets(
      '$failure exposes settings and reload works after granting access',
      (tester) async {
        final device = _Device()..failure = DeviceLocationException(failure);
        final controller = NearbyLocationController(service: device);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WorkerNearbyLocationPanel(controller: controller),
            ),
          ),
        );
        await controller.refresh();
        await tester.pump();
        await tester.tap(find.text('Open settings'));
        await tester.pumpAndSettle();
        expect(device.settings, 1);
        device.failure = null;
        device.granted = true;
        await controller.refresh();
        await tester.pumpAndSettle();
        expect(controller.position, same(device.position));
        expect(find.text('Refresh nearby jobs'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }
}
