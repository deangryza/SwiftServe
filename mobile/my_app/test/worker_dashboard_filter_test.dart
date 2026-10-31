import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/worker/presentation/screens/worker_home_screen.dart';
import 'package:my_app/features/worker/presentation/screens/worker_search_screen.dart';
import 'package:my_app/shared/models/service_application.dart';
import 'package:my_app/shared/models/service_request.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/utils/job_location_utils.dart';

void main() {
  const home = JobCoordinate(latitude: 14.84, longitude: 120.81);
  List<ServiceRequest> nearby(
    Iterable<ServiceRequest> jobs, {
    JobCoordinate? origin = home,
    Iterable<ServiceApplication> applications = const [],
  }) => filterWorkerDashboardRequests(
    workerId: 'worker',
    requests: jobs,
    applications: applications,
    filter: WorkerDashboardRequestFilter.nearby,
    workerCurrentPosition: origin,
  );

  test('nearby uses current GPS radius and sorts nearest first', () {
    final jobs = [
      _request('far', DateTime(2026), latitude: 15.84),
      _request('middle', DateTime(2026), latitude: 14.89),
      _request('nearest', DateTime(2025), latitude: 14.841),
      _request('outside-radius', DateTime(2026), latitude: 14.94),
    ];
    expect(nearby(jobs).map((job) => job.id), ['nearest', 'middle']);
    // A different current location changes which jobs qualify.
    expect(
      nearby(
        jobs,
        origin: const JobCoordinate(latitude: 15.84, longitude: 120.81),
      ).map((job) => job.id),
      ['far'],
    );
  });

  test(
    'nearby includes all 65 eligible results rather than the five Recent results',
    () {
      final jobs = List.generate(
        65,
        (i) =>
            _request('job-$i', DateTime(2026), latitude: 14.84 + i * 0.00001),
      );
      expect(nearby(jobs), hasLength(65));
      expect(
        filterWorkerDashboardRequests(
          workerId: 'worker',
          requests: jobs,
          applications: [],
          filter: WorkerDashboardRequestFilter.recent,
        ),
        hasLength(5),
      );
    },
  );
  test('10 km boundary is inclusive and points just outside are excluded', () {
    const origin = JobCoordinate(latitude: 0, longitude: 120.81);
    final latitude = 10000 / 6371000 * 180 / math.pi;
    final boundary = _request('boundary', DateTime(2026), latitude: latitude);
    expect(
      distanceMetersBetween(origin, boundary.areaPosition!),
      closeTo(10000, 0.000001),
    );
    expect(
      nearby([
        _request('inside', DateTime(2026), latitude: latitude - 0.000001),
        boundary,
        _request('outside', DateTime(2026), latitude: latitude + 0.000001),
      ], origin: origin).map((r) => r.id),
      ['inside', 'boundary'],
    );
  });
  test(
    'nearby rejects invalid coordinates and all reached stored deadlines',
    () {
      final now = DateTime.utc(2026, 10, 29, 4);
      final jobs = [
        _request('invalid', DateTime(2026), latitude: double.nan),
        _request('range', DateTime(2026), latitude: 91),
        _request(
          'expired',
          DateTime(2026),
          latitude: 14.84,
          start: DateTime.utc(2026, 10, 29, 1),
        ),
        _request(
          'future',
          DateTime(2026),
          latitude: 14.84,
          start: DateTime.utc(2026, 10, 30, 1),
        ),
        _request(
          'legacy-midnight',
          DateTime(2026),
          latitude: 14.84,
          start: DateTime.utc(2026, 10, 28, 16),
        ),
      ];
      final result = filterWorkerDashboardRequests(
        workerId: 'worker',
        requests: jobs,
        applications: [],
        filter: WorkerDashboardRequestFilter.nearby,
        workerCurrentPosition: home,
        now: now,
      );
      // Midnight is ambiguous for automatic expiration policy, but must no
      // longer allow a new application after its stored start has been reached.
      expect(result.map((r) => r.id), ['future']);
      expect(
        nearby(
          jobs,
          origin: const JobCoordinate(
            latitude: double.infinity,
            longitude: 120,
          ),
        ),
        isEmpty,
      );
    },
  );

  test(
    'nearby excludes online and unlocated jobs, includes hybrid and errands',
    () {
      final jobs = [
        _request('no-pin', DateTime(2026)),
        _request(
          'online',
          DateTime(2026),
          latitude: 14.84,
          modality: JobModality.online,
        ),
        _request(
          'hybrid',
          DateTime(2026),
          latitude: 14.841,
          modality: JobModality.hybrid,
        ),
        _request(
          'errand-pickup',
          DateTime(2026),
          latitude: 14.842,
          modality: JobModality.errand,
        ),
      ];
      expect(nearby(jobs).map((job) => job.id), ['hybrid', 'errand-pickup']);
    },
  );

  test(
    'nearby never falls back to all jobs without a resolved current location',
    () {
      expect(
        nearby([
          _request('near', DateTime(2026), latitude: 14.84),
        ], origin: null),
        isEmpty,
      );
    },
  );

  test('nearby keeps pending unapplied jobs only', () {
    final jobs = [
      _request('applied', DateTime(2026), latitude: 14.84),
      _request(
        'accepted',
        DateTime(2026),
        latitude: 14.84,
        status: ServiceRequestStatus.accepted,
      ),
      _request('open', DateTime(2026), latitude: 14.84),
    ];
    expect(
      nearby(
        jobs,
        applications: const [
          ServiceApplication(
            workerId: 'worker',
            workerName: 'Worker',
            requestId: 'applied',
            clientId: 'client-1',
            status: ServiceApplicationStatus.pending,
          ),
        ],
      ).map((job) => job.id),
      ['open'],
    );
  });

  test('nearby keeps newest first for jobs at the same distance', () {
    expect(
      nearby([
        _request('older', DateTime(2025), latitude: 14.84),
        _request('newer', DateTime(2026), latitude: 14.84),
      ]).map((job) => job.id),
      ['newer', 'older'],
    );
  });
  test('applied requests are removed and recent requests are newest first', () {
    final requests = List.generate(
      7,
      (index) => _request('request-$index', DateTime(2026, 10, index + 1)),
    );
    final applications = [
      const ServiceApplication(
        workerId: 'worker-1',
        workerName: 'Worker One',
        requestId: 'request-6',
        clientId: 'client-1',
        status: ServiceApplicationStatus.pending,
      ),
    ];

    final recent = filterWorkerDashboardRequests(
      workerId: 'worker',
      requests: requests,
      applications: applications,
      filter: WorkerDashboardRequestFilter.recent,
    );
    final available = filterWorkerDashboardRequests(
      workerId: 'worker',
      requests: requests,
      applications: applications,
      filter: WorkerDashboardRequestFilter.available,
    );

    expect(recent.map((request) => request.id), [
      'request-5',
      'request-4',
      'request-3',
      'request-2',
      'request-1',
    ]);
    expect(available, hasLength(6));
    expect(available.any((request) => request.id == 'request-6'), isFalse);
  });

  test('non-pending requests never appear as available jobs', () {
    final accepted = _request(
      'accepted-request',
      DateTime(2026, 10, 10),
      status: ServiceRequestStatus.accepted,
    );

    final visible = filterWorkerDashboardRequests(
      workerId: 'worker',
      requests: [accepted],
      applications: const [],
      filter: WorkerDashboardRequestFilter.available,
    );

    expect(visible, isEmpty);
  });

  test('dashboard search matches service, client, and location text', () {
    final request = _request('request-1', DateTime(2026, 10, 10));

    expect(matchesWorkerSearchRequest(request, 'math'), isTrue);
    expect(matchesWorkerSearchRequest(request, 'academic'), isTrue);
    expect(matchesWorkerSearchRequest(request, 'client one'), isTrue);
    expect(matchesWorkerSearchRequest(request, 'malolos'), isTrue);
    expect(matchesWorkerSearchRequest(request, 'plumbing'), isFalse);
    expect(matchesWorkerSearchRequest(request, '  '), isTrue);
  });

  test('dashboard search checks all available jobs beyond the recent five', () {
    final requests = List.generate(
      7,
      (index) => _request(
        'request-$index',
        DateTime(2026, 10, index + 1),
        title: index == 0 ? 'Rare piano tuning' : 'House cleaning',
      ),
    );
    final eligible = filterWorkerDashboardRequests(
      workerId: 'worker',
      requests: requests,
      applications: const [],
      filter: WorkerDashboardRequestFilter.available,
    );

    final matches = availableWorkerSearchRequests(
      workerId: 'worker',
      requests: eligible,
      applications: const [],
      query: 'piano',
    );

    expect(matches.map((request) => request.id), ['request-0']);
  });
}

ServiceRequest _request(
  String id,
  DateTime createdAt, {
  ServiceRequestStatus status = ServiceRequestStatus.pending,
  String title = 'Math tutoring',
  double? latitude,
  JobModality modality = JobModality.onsite,
  DateTime? start,
}) => ServiceRequest(
  id: id,
  clientId: 'client-1',
  clientName: 'Client One',
  title: title,
  category: 'Academic Help',
  location: 'Malolos',
  description: 'Help with algebra',
  budget: 500,
  status: status,
  createdAt: createdAt,
  scheduleFrom: start,
  modality: modality,
  areaLatitude: latitude,
  areaLongitude: latitude == null ? null : 120.81,
);
