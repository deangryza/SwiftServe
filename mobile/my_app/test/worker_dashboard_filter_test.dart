import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/worker/presentation/screens/worker_home_screen.dart';
import 'package:my_app/features/worker/presentation/screens/worker_search_screen.dart';
import 'package:my_app/shared/models/service_application.dart';
import 'package:my_app/shared/models/service_request.dart';

void main() {
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
      requests: requests,
      applications: applications,
      filter: WorkerDashboardRequestFilter.recent,
    );
    final available = filterWorkerDashboardRequests(
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
      requests: requests,
      applications: const [],
      filter: WorkerDashboardRequestFilter.available,
    );

    final matches = availableWorkerSearchRequests(
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
);
