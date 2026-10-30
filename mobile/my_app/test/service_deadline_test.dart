import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/models/service_request.dart';
import 'package:my_app/shared/utils/service_schedule.dart';
import 'package:my_app/shared/widgets/service_deadline_builder.dart';
import 'package:my_app/features/worker/presentation/screens/worker_home_screen.dart';
import 'package:my_app/features/worker/presentation/screens/worker_search_screen.dart';
import 'package:my_app/shared/models/job_location.dart';

ServiceRequest job(DateTime? start, {String status = 'pending'}) =>
    ServiceRequest.fromMap('job', {
      'clientId': 'client',
      'status': status,
      'scheduleFrom': start == null ? null : Timestamp.fromDate(start),
      'areaPosition': const GeoPoint(14.84, 120.81),
    });

void main() {
  test(
    'PHT midnight and 1:34 AM use absolute instants and inclusive deadline',
    () {
      for (final time in [
        const TimeOfDay(hour: 0, minute: 0),
        const TimeOfDay(hour: 1, minute: 34),
      ]) {
        final start = serviceStartInstant(DateTime(2026, 10, 30), time);
        expect(start.day, 29);
        expect(
          job(start).applicationDeadlineReached(
            now: start.subtract(const Duration(microseconds: 1)),
          ),
          isFalse,
        );
        expect(job(start).applicationDeadlineReached(now: start), isTrue);
        expect(
          job(start).applicationDeadlineReached(
            now: start.add(const Duration(microseconds: 1)),
          ),
          isTrue,
        );
      }
    },
  );

  test(
    'all discovery filters close at the same deadline, including legacy schedule-only',
    () {
      final now = DateTime.utc(2026, 10, 29, 16);
      final requests = [job(now), job(now.add(const Duration(hours: 1)))];
      for (final filter in WorkerDashboardRequestFilter.values) {
        expect(
          filterWorkerDashboardRequests(
            workerId: 'worker',
            requests: requests,
            applications: const [],
            filter: filter,
            now: now,
            workerCurrentPosition: const JobCoordinate(
              latitude: 14.84,
              longitude: 120.81,
            ),
          ),
          [requests.last],
        );
      }
      expect(
        availableWorkerSearchRequests(
          workerId: 'worker',
          requests: requests,
          applications: const [],
          query: '',
          now: now,
        ),
        [requests.last],
      );
      final legacy = ServiceRequest.fromMap('legacy', {
        'clientId': 'client',
        'schedule': Timestamp.fromDate(now),
      });
      expect(legacy.isAvailableToWorker('worker', now: now), isFalse);
      expect(job(null).isAvailableToWorker('worker', now: now), isTrue);
      expect(
        job(
          now.add(const Duration(days: 1)),
          status: 'expired',
        ).isAvailableToWorker('worker', now: now),
        isFalse,
      );
    },
  );

  testWidgets(
    'availability refreshes at each deadline without a Firestore event',
    (tester) async {
      var now = DateTime.utc(2026, 10, 30);
      final first = job(now.add(const Duration(seconds: 1)));
      final second = job(now.add(const Duration(seconds: 2)));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ServiceDeadlineBuilder(
            requests: [first, second],
            now: () => now,
            builder: (_, instant) => Text(
              '${[first, second].where((j) => j.isAvailableToWorker('worker', now: instant)).length} open',
            ),
          ),
        ),
      );
      expect(find.text('2 open'), findsOneWidget);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1 open'), findsOneWidget);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0 open'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'resume refreshes overdue availability and disposal cancels timers',
    (tester) async {
      var now = DateTime.utc(2026, 10, 30);
      final request = job(now.add(const Duration(hours: 1)));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ServiceDeadlineBuilder(
            requests: [request],
            now: () => now,
            builder: (_, instant) => Text(
              request.isAvailableToWorker('worker', now: instant)
                  ? 'open'
                  : 'closed',
            ),
          ),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = now.add(const Duration(hours: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('closed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(hours: 3));
      expect(tester.takeException(), isNull);
    },
  );
}
