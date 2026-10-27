import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:my_app/features/worker/presentation/screens/worker_job_details_screen.dart';
import 'package:my_app/features/worker/presentation/screens/worker_search_screen.dart';
import 'package:my_app/shared/models/app_user.dart';
import 'package:my_app/shared/models/service_request.dart';
import 'package:my_app/shared/theme/app_theme.dart';

const worker = AppUser(
  id: 'worker-1',
  fullName: 'Worker One',
  email: 'worker@example.com',
  role: UserRole.worker,
  verificationStatus: VerificationStatus.verified,
);

ServiceRequest request(
  JobModality modality,
  ServiceRequestStatus status, {
  bool mapped = false,
}) => ServiceRequest(
  id: 'request-1',
  clientId: 'client-1',
  clientName: 'Client One',
  title: 'Help with a task',
  category: 'Other',
  location: modality == JobModality.online ? 'Online' : 'Malolos',
  description: 'Please help with this task.',
  budget: 100,
  status: status,
  modality: modality,
  workerId: worker.id,
  dropoffLocation: modality == JobModality.errand ? 'Bulakan' : null,
  errandItems: modality == JobModality.errand ? '2 kg rice' : null,
  distanceKm: modality == JobModality.errand ? 5 : null,
  areaLatitude: mapped ? 14.8441 : null,
  areaLongitude: mapped ? 120.8119 : null,
  dropoffLatitude: mapped ? 14.79 : null,
  dropoffLongitude: mapped ? 120.88 : null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async =>
              call.method == 'isLocationServiceEnabled' ? false : null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          null,
        );
  });

  test('dedicated worker search retains remote work-type matching', () {
    for (final modality in JobModality.values) {
      expect(
        matchesWorkerSearchRequest(
          request(modality, ServiceRequestStatus.pending),
          modality.label,
        ),
        isTrue,
        reason: modality.name,
      );
    }
  });

  testWidgets('errand details retain profile access and start confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: WorkerJobDetailsScreen(
          request: request(JobModality.errand, ServiceRequestStatus.accepted),
          worker: worker,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delivery fee'), findsOneWidget);
    expect(find.text('Pickup: Malolos'), findsOneWidget);
    expect(find.text('Drop-off: Bulakan'), findsOneWidget);
    expect(find.text('2 kg rice'), findsOneWidget);

    final profile = find.byKey(const ValueKey('view-client-profile'));
    await tester.scrollUntilVisible(profile, 150);
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(profile);
    expect(button.style!.backgroundColor!.resolve({}), AppTheme.yellow);
    expect(button.onPressed, isNotNull);

    await tester.scrollUntilVisible(find.text('Start errand'), 150);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start errand'));
    await tester.pumpAndSettle();
    expect(find.text('Start this booking?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Start this booking?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('online work retains completion confirmation without a map', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: WorkerJobDetailsScreen(
          request: request(JobModality.online, ServiceRequestStatus.ongoing),
          worker: worker,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Online · done remotely'), findsOneWidget);
    expect(find.text('Exact job location'), findsNothing);
    await tester.scrollUntilVisible(find.text('Mark completed'), 150);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark completed'));
    await tester.pumpAndSettle();
    expect(find.text('Complete this booking?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Complete this booking?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('errand map renders inside the redesigned outlined card', (
    tester,
  ) async {
    // Ahem's fixed-width glyphs artificially overflow the map attribution.
    // Load Flutter's own Roboto font for this layout check.
    await tester.runAsync(() async {
      final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
      final bytes = await File(
        '${artifacts.path}/material_fonts/roboto-regular.ttf',
      ).readAsBytes();
      await (FontLoader(
        'MapTestFont',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    });
    final theme = AppTheme.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'MapTestFont'),
        ),
        home: WorkerJobDetailsScreen(
          request: request(
            JobModality.errand,
            ServiceRequestStatus.accepted,
            mapped: true,
          ),
          worker: worker,
        ),
      ),
    );
    await tester.scrollUntilVisible(find.byType(FlutterMap), 150);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Approximate pickup area'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
