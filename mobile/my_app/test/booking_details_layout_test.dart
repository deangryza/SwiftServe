import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/client/presentation/screens/client_booking_flow.dart';
import 'package:my_app/features/client/presentation/screens/client_request_details_screen.dart';
import 'package:my_app/features/client/presentation/widgets/errand_tracking_map.dart';
import 'package:my_app/features/client/presentation/widgets/post_location_map.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/repositories/service_request_repository.dart';
import 'package:my_app/shared/models/service_request.dart';
import 'package:my_app/shared/theme/app_theme.dart';
import 'package:my_app/shared/widgets/booking_details_cards.dart';
import 'package:my_app/shared/widgets/sos_button.dart';

class _MissingLocationRepository extends Fake
    implements ServiceRequestRepository {
  _MissingLocationRepository(this.request);
  final ServiceRequest request;
  @override
  Future<ExactJobLocation?> getExactLocation(String requestId) async => null;
  @override
  Stream<ExactJobLocation?> watchExactLocation(String requestId) =>
      Stream.value(null);
  @override
  Stream<ServiceRequest?> watchRequest(String requestId) =>
      Stream.value(request);
}

ServiceRequest booking({
  JobModality modality = JobModality.onsite,
  ServiceRequestStatus status = ServiceRequestStatus.accepted,
  ErrandStage? stage,
  String? workerId,
}) => ServiceRequest(
  id: 'booking-test',
  clientId: 'client-test',
  clientName: 'Client Name',
  workerId: workerId,
  workerName: 'Worker Name',
  title: 'Help with a household task',
  category: 'Home Services',
  location: '123 Example Street, Bulihan, Malolos, Bulacan',
  dropoffLocation: modality == JobModality.errand
      ? '456 Example Avenue, Guinhawa, Malolos, Bulacan'
      : null,
  description: 'Please contact me when you arrive. Handle the items carefully.',
  budget: 105,
  status: status,
  modality: modality,
  errandStage: stage,
  errandItems: modality == JobModality.errand ? 'Household supplies' : null,
  itemCostEstimate: modality == JobModality.errand ? 300 : null,
  distanceKm: modality == JobModality.errand ? 5.5 : null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final bytes = await File(
      '${artifacts.path}/material_fonts/roboto-regular.ttf',
    ).readAsBytes();
    await (FontLoader(
      'BookingTestFont',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    final iconBytes = await File(
      '${artifacts.path}/material_fonts/materialicons-regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(iconBytes)))).load();
  });

  for (final status in ServiceRequestStatus.values) {
    test(
      'service progress maps ${status.name} without introducing transitions',
      () {
        expect(bookingProgressIndex(booking(status: status)), switch (status) {
          ServiceRequestStatus.accepted => 0,
          ServiceRequestStatus.ongoing => 1,
          ServiceRequestStatus.completed => 2,
          _ => -1,
        });
      },
    );
  }
  for (final stage in ErrandStage.values) {
    test(
      'errand progress maps ${stage.name} without claiming an early pickup',
      () {
        expect(
          bookingProgressIndex(
            booking(
              modality: JobModality.errand,
              status: ServiceRequestStatus.ongoing,
              stage: stage,
            ),
          ),
          switch (stage) {
            ErrandStage.pickedUp => 0,
            ErrandStage.delivering => 1,
            _ => -1,
          },
        );
      },
    );
  }
  test(
    'legacy, accepted and cancelled errands never invent a completed stage',
    () {
      for (final status in [
        ServiceRequestStatus.pending,
        ServiceRequestStatus.accepted,
        ServiceRequestStatus.ongoing,
        ServiceRequestStatus.cancelled,
      ]) {
        expect(
          bookingProgressIndex(
            booking(modality: JobModality.errand, status: status),
          ),
          -1,
        );
      }
      expect(
        bookingProgressIndex(
          booking(
            modality: JobModality.errand,
            status: ServiceRequestStatus.completed,
          ),
        ),
        2,
      );
    },
  );

  ThemeData theme({bool dark = false}) {
    final base = dark ? ThemeData.dark(useMaterial3: true) : AppTheme.light;
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'BookingTestFont'),
    );
  }

  testWidgets(
    'client maps explain missing coordinates without inventing a pin',
    (tester) async {
      final request = booking(modality: JobModality.errand);
      final repository = _MissingLocationRepository(request);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme(),
          home: Scaffold(
            body: ErrandTrackingMap(
              request: request,
              repository: repository,
              showTimeline: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Map unavailable for this booking.'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme(),
          home: Scaffold(
            body: PostLocationMap(request: request, repository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No location pinned for this post.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final status in ServiceRequestStatus.values) {
    testWidgets(
      'post details share booking cards and preserve ${status.name} actions',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var edits = 0;
        var cancellations = 0;
        var messages = 0;
        var profiles = 0;
        var reviews = 0;
        final pending = status == ServiceRequestStatus.pending;
        final request = booking(
          modality: JobModality.online,
          status: status,
          workerId: pending ? null : 'selected-worker',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: ClientRequestDetailsContent(
                request: request,
                dateLabel: 'Flexible',
                saving: false,
                onEdit: () => edits++,
                onCancel: () => cancellations++,
                onMessage: () => messages++,
                onViewProfile: () => profiles++,
                onRate: () => reviews++,
                applications: pending
                    ? const Text('Existing applications')
                    : null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BookingDetailsHeader), findsOneWidget);
        expect(find.byType(BookingFeeProgressCard), findsOneWidget);
        expect(find.byType(SosButton), findsNothing);
        if (pending) {
          expect(find.text('No worker assigned yet.'), findsOneWidget);
          expect(find.byType(BookingPartyCard), findsNothing);
          await tester.tap(find.byKey(const ValueKey('request-details-edit')));
          expect(edits, 1);
        } else {
          final party = tester.widget<BookingPartyCard>(
            find.byType(BookingPartyCard),
          );
          expect(party.userId, 'selected-worker');
          expect(party.name, 'Worker Name');
          await tester.tap(find.byKey(const ValueKey('view-worker-profile')));
          expect(profiles, 1);
          if (status != ServiceRequestStatus.cancelled) {
            await tester.tap(
              find.byKey(const ValueKey('message-accepted-worker')),
            );
            expect(messages, 1);
          } else {
            expect(
              find.byKey(const ValueKey('message-accepted-worker')),
              findsNothing,
            );
          }
          expect(
            find.byKey(const ValueKey('request-details-edit')),
            findsNothing,
          );
        }
        if (pending || status == ServiceRequestStatus.accepted) {
          final cancel = find.text('Cancel request');
          await tester.scrollUntilVisible(cancel, 150);
          await tester.pumpAndSettle();
          await tester.tap(cancel);
          expect(cancellations, 1);
        } else {
          expect(find.text('Cancel request'), findsNothing);
        }
        if (status == ServiceRequestStatus.completed) {
          final rate = find.text('Rate worker');
          await tester.scrollUntilVisible(rate, 150);
          await tester.pumpAndSettle();
          await tester.tap(rate);
          expect(reviews, 1);
        }
        expect(find.text('Mark as picked up'), findsNothing);
        expect(find.text('Mark as completed'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  Future<void> pump(WidgetTester tester, Widget child, {bool dark = false}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: theme(dark: dark),
          home: Scaffold(body: SafeArea(child: child)),
        ),
      );

  testWidgets(
    'fee and three stages are informational, with real fee and trip values',
    (tester) async {
      await pump(
        tester,
        BookingFeeProgressCard(
          request: booking(
            modality: JobModality.errand,
            status: ServiceRequestStatus.ongoing,
            stage: ErrandStage.delivering,
          ),
        ),
      );
      expect(find.text('₱105'), findsOneWidget);
      expect(find.text('~5.5 km trip'), findsOneWidget);
      expect(find.text('Picked up'), findsOneWidget);
      expect(find.text('On the way'), findsOneWidget);
      expect(find.text('Delivered'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('booking-progress-1-active')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('booking-progress-2-waiting')),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsNothing);
    },
  );

  testWidgets(
    'online bookings have service stages and no fabricated trip distance',
    (tester) async {
      await pump(
        tester,
        BookingFeeProgressCard(request: booking(modality: JobModality.online)),
      );
      expect(find.text('Accepted'), findsNWidgets(2));
      expect(find.text('In progress'), findsOneWidget);
      expect(find.textContaining('km trip'), findsNothing);
      expect(find.text('Picked up'), findsNothing);
    },
  );

  testWidgets(
    'compact person card preserves both action callbacks and accessible labels',
    (tester) async {
      var messages = 0;
      var profiles = 0;
      await pump(
        tester,
        BookingPartyCard(
          userId: 'worker',
          name: 'Worker Name',
          role: 'Worker',
          profileKey: const ValueKey('profile'),
          messageKey: const ValueKey('message'),
          onViewProfile: () => profiles++,
          onMessage: () => messages++,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('profile')));
      await tester.tap(find.byKey(const ValueKey('message')));
      expect(messages, 1);
      expect(profiles, 1);
      expect(find.byTooltip('Message Worker'), findsOneWidget);
      expect(find.byTooltip('View Worker profile'), findsOneWidget);
    },
  );

  testWidgets(
    'client details preserve message/cancel actions and only one SOS entry',
    (tester) async {
      var messages = 0;
      var cancellations = 0;
      await pump(
        tester,
        ClientBookingDetailsContent(
          request: booking(),
          worker: const {'fullName': 'Worker Name'},
          saving: false,
          savingReview: false,
          savingReport: false,
          onRateWorker: () {},
          onReportWorker: () {},
          onMessage: () => messages++,
          onCancel: () => cancellations++,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SosButton), findsOneWidget);
      expect(find.byKey(const ValueKey('sos-button-compact')), findsOneWidget);
      expect(find.text('Message Worker'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('message-accepted-worker')));
      expect(messages, 1);
      final cancel = find.text('Cancel Request');
      await tester.scrollUntilVisible(cancel, 150);
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      expect(cancellations, 1);
      final sos = find.byKey(const ValueKey('sos-button-compact'));
      await tester.tap(sos);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sos-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sos-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sos-confirm')), findsNothing);
    },
  );

  testWidgets(
    'client completed review stays available without status-only or cancel buttons',
    (tester) async {
      var reviews = 0;
      await pump(
        tester,
        ClientBookingDetailsContent(
          request: booking(status: ServiceRequestStatus.completed),
          worker: const {'fullName': 'Worker Name'},
          saving: false,
          savingReview: false,
          savingReport: false,
          onRateWorker: () => reviews++,
          onReportWorker: () {},
          onMessage: () {},
          onCancel: () {},
        ),
      );
      await tester.pumpAndSettle();
      final review = find.byKey(const ValueKey('rate-completed-worker'));
      await tester.scrollUntilVisible(review, 150);
      await tester.pumpAndSettle();
      await tester.tap(review);
      expect(reviews, 1);
      expect(find.text('Cancel Request'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'long addresses and details fit a small screen in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final request = booking(
          modality: JobModality.errand,
          status: ServiceRequestStatus.completed,
        );
        await pump(
          tester,
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  BookingPartyCard(
                    userId: '',
                    name: 'A worker with a very long professional display name',
                    role: 'Worker',
                    profileKey: const ValueKey('profile'),
                    messageKey: const ValueKey('message'),
                    onViewProfile: () {},
                    onMessage: () {},
                  ),
                  BookingFeeProgressCard(request: request),
                  BookingRouteCard(request: request),
                  BookingInformationCard(
                    request: request,
                    dateLabel: '10/26/2026 – 10/28/2026',
                  ),
                ],
              ),
            ),
          ),
          dark: dark,
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Client note'), 180);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('₱300 (paid back on delivery)'), findsOneWidget);
      },
    );
  }

  testWidgets('render the compact client booking layout for visual review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(
      tester,
      RepaintBoundary(
        key: const ValueKey('booking-preview'),
        child: ColoredBox(
          color: AppTheme.light.colorScheme.surfaceContainer,
          child: ClientBookingDetailsContent(
            request: booking(),
            worker: const {'fullName': 'Worker Name'},
            saving: false,
            savingReview: false,
            savingReport: false,
            onRateWorker: () {},
            onReportWorker: () {},
            onMessage: () {},
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final output = Platform.environment['SWIFTSERVE_BOOKING_PREVIEW_PATH'];
    if (output != null) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('booking-preview')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(output).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
  });
}
