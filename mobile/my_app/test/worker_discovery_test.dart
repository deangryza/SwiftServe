import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/models/discovered_worker.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/repositories/worker_discovery_repository.dart';
import 'package:my_app/shared/services/device_location_service.dart';
import 'package:my_app/shared/services/job_geocoding_service.dart';
import 'package:my_app/shared/services/worker_discovery_service.dart';

DiscoveredWorker worker(
  String id, {
  double? meters,
  String? address,
  String status = 'verified',
  String? role,
}) => DiscoveredWorker(
  id: id,
  distanceMeters: meters,
  data: {
    'fullName': 'Worker $id',
    'workerId': id,
    'verificationStatus': status,
    'location': address ?? '',
    'role': role ?? 'worker',
  },
);

class _Source implements WorkerDiscoverySource {
  Map<String, dynamic>? profile = {
    'address': '123 Client Street, Brgy. Client, Exampletown, Province',
  };
  final pages = <List<DiscoveredWorker>>[];
  int reads = 0;
  int pageIndex = 0;
  int restarts = 0;
  bool fail = false;
  String? requestedClient;
  String? requestedWorker;
  WorkerConversation? existing;
  @override
  void restart() {
    pageIndex = 0;
    restarts++;
  }

  @override
  Future<Map<String, dynamic>?> clientProfile(String clientId) async => profile;
  @override
  Future<WorkerDiscoveryPage> nextWorkers() async {
    if (fail) throw StateError('Firestore unavailable');
    reads++;
    final page = pageIndex++;
    return WorkerDiscoveryPage(
      page < pages.length ? pages[page] : [],
      hasMore: page + 1 < pages.length,
    );
  }

  @override
  Future<WorkerConversation?> conversation(
    String clientId,
    String workerId,
  ) async {
    requestedClient = clientId;
    requestedWorker = workerId;
    return existing;
  }
}

class _Resolver extends Fake implements JobAddressResolver {
  final calls = <String>[];
  final coordinates = <String, JobCoordinate>{
    // The old implementation could resolve these private details; regression
    // assertions must prove they are no longer sent, rather than fail by chance.
    '123 Client Street, Brgy. Client, Exampletown, Province':
        const JobCoordinate(latitude: 14.84, longitude: 120.81),
    'Brgy. Client, Exampletown': const JobCoordinate(
      latitude: 14.84,
      longitude: 120.81,
    ),
    'Brgy. Nearby, Exampletown': const JobCoordinate(
      latitude: 14.841,
      longitude: 120.81,
    ),
    'Brgy. Far, Exampletown': const JobCoordinate(
      latitude: 15.84,
      longitude: 120.81,
    ),
  };
  @override
  Future<JobLocationSelection> search(String address) async {
    calls.add(address);
    final coordinate = coordinates[address];
    if (coordinate == null) throw StateError('Address unavailable');
    return JobLocationSelection(
      position: coordinate,
      exactAddress: address,
      areaLabel: address,
    );
  }
}

class _Location extends DeviceLocationService {
  bool denied = false;
  int calls = 0;
  @override
  Future<JobCoordinate> currentPosition() async {
    calls++;
    if (denied) {
      throw const DeviceLocationException(
        DeviceLocationFailure.permissionDenied,
      );
    }
    return const JobCoordinate(latitude: 15.84, longitude: 120.81);
  }
}

void main() {
  test(
    'worker discovery geocodes the public locality, never the residential address',
    () async {
      const exact = '123 Example Street, Brgy. Ligas, Malolos, Bulacan';
      final source = _Source()
        ..pages.add([worker('private-worker', address: exact)]);
      final resolver = _Resolver()
        ..coordinates.addAll({
          exact: const JobCoordinate(latitude: 14.841, longitude: 120.81),
          'Brgy. Ligas, Malolos': const JobCoordinate(
            latitude: 14.841,
            longitude: 120.81,
          ),
        });
      final service = WorkerDiscoveryService(
        clientId: 'client',
        source: source,
        resolver: resolver,
      );
      final result = await service.nextBatch();
      expect(result.workers.single.isNearby, isTrue);
      expect(result.workers.single.publicLocationLabel, 'Brgy. Ligas, Malolos');
      expect(resolver.calls, contains('Brgy. Ligas, Malolos'));
      expect(resolver.calls, isNot(contains(exact)));
      expect(resolver.calls, isNot(contains(source.profile!['address'])));
    },
  );

  test(
    'unrecognized residential address produces a suggestion without geocoding it',
    () async {
      final source = _Source()
        ..pages.add([worker('private-worker', address: '123 Example Street')]);
      final resolver = _Resolver();
      final result = await WorkerDiscoveryService(
        clientId: 'client',
        source: source,
        resolver: resolver,
      ).nextBatch();
      expect(result.workers.single.isNearby, isFalse);
      expect(result.workers.single.distanceMeters, isNull);
      expect(
        result.workers.single.publicLocationLabel,
        'Location not provided',
      );
      expect(resolver.calls, isNot(contains('123 Example Street')));
    },
  );

  test('nearby includes zero through exactly 10 km, sorted nearest first', () {
    final result = nextWorkerRecommendations(
      workers: [
        worker('boundary', meters: 10000),
        worker('far', meters: 10000.01),
        worker('near', meters: 50),
        worker('same-place', meters: 0),
      ],
      clientId: 'client',
      seenIds: {},
    );
    expect(result.map((w) => w.id), ['same-place', 'near', 'boundary']);
    expect(result.every((w) => w.isNearby), isTrue);
  });

  test(
    'eligibility excludes self, unverified and non-worker accounts; IDs are unique',
    () {
      final result = nextWorkerRecommendations(
        workers: [
          worker('client', meters: 1),
          worker('pending', status: 'pending'),
          worker('not-worker', role: 'client'),
          worker('one', meters: 2),
          worker('one', meters: 2),
          const DiscoveredWorker(
            id: 'wrong-id',
            data: {'workerId': 'other', 'verificationStatus': 'verified'},
          ),
        ],
        clientId: 'client',
        seenIds: {},
      );
      expect(result.map((w) => w.id), ['one']);
    },
  );

  test(
    'refresh shows at most ten, drains nearby then suggestions before repeating',
    () {
      final workers = [
        for (var i = 0; i < 15; i++) worker('near-$i', meters: i.toDouble()),
        worker('far', meters: 20000),
        worker('unknown'),
      ];
      final seen = <String>{};
      List<DiscoveredWorker> next() => nextWorkerRecommendations(
        workers: workers,
        clientId: 'client',
        seenIds: seen,
      );
      final first = next();
      final second = next();
      final suggested = next();
      final repeated = next();
      expect(first, hasLength(10));
      expect(second, hasLength(5));
      expect(
        first
            .map((w) => w.id)
            .toSet()
            .intersection(second.map((w) => w.id).toSet()),
        isEmpty,
      );
      expect(suggested.map((w) => w.id), ['far', 'unknown']);
      expect(suggested.every((w) => !w.isNearby), isTrue);
      expect(repeated.map((w) => w.id), first.map((w) => w.id));
    },
  );

  test('missing, negative and nonfinite distances are never nearby', () {
    for (final distance in [null, double.nan, double.infinity, -1.0]) {
      final entry = worker('worker', meters: distance);
      expect(entry.isNearby, isFalse);
      expect(entry.distanceLabel, 'Distance unavailable');
    }
    expect(
      nextWorkerRecommendations(workers: [], clientId: 'client', seenIds: {}),
      isEmpty,
    );
  });

  late _Source source;
  late _Resolver resolver;
  late _Location location;
  late WorkerDiscoveryService service;
  setUp(() {
    source = _Source();
    resolver = _Resolver();
    location = _Location();
    service = WorkerDiscoveryService(
      clientId: 'client',
      source: source,
      resolver: resolver,
      location: location,
    );
  });

  test(
    'refresh re-reads the directory after all workers have been shown',
    () async {
      source.pages.add([worker('old', address: 'Brgy. Nearby, Exampletown')]);
      expect((await service.nextBatch()).workers.single.id, 'old');
      source.pages[0] = [worker('new', address: 'Brgy. Nearby, Exampletown')];
      expect((await service.nextBatch()).workers.single.id, 'new');
      expect(source.restarts, 1);
      expect(source.reads, 2);
    },
  );

  test(
    'repeated profile IDs are deduplicated and changed locations are recalculated',
    () async {
      source.pages.addAll([
        [worker('a', address: 'Brgy. Nearby, Exampletown')],
        [
          worker('a', address: 'Brgy. Far, Exampletown'),
          worker('b', address: 'Brgy. Nearby, Exampletown'),
        ],
      ]);
      expect((await service.nextBatch()).workers.single.id, 'a');
      expect((await service.nextBatch()).workers.single.id, 'b');
      expect(resolver.calls, contains('Brgy. Far, Exampletown'));
    },
  );

  test(
    'real resolved coordinates determine distances; successful lookups are cached',
    () async {
      source.pages.addAll([
        [worker('a', address: 'Brgy. Nearby, Exampletown')],
        [worker('b', address: 'Brgy. Nearby, Exampletown')],
      ]);
      final first = await service.nextBatch();
      expect(first.workers.single.distanceMeters, inInclusiveRange(110, 112));
      expect(first.workers.single.isNearby, isTrue);
      final next = await service.nextBatch();
      expect(next.workers.single.id, 'b');
      expect(source.reads, 2);
      expect(
        resolver.calls.where((q) => q == 'Brgy. Nearby, Exampletown'),
        hasLength(1),
      );
      expect(
        resolver.calls.where((q) => q == 'Brgy. Client, Exampletown'),
        hasLength(1),
      );
      expect(location.calls, 0);
    },
  );

  test(
    'unknown client location returns clearly described suggestions',
    () async {
      source.profile = null;
      source.pages.add([worker('a', address: 'Brgy. Nearby, Exampletown')]);
      final result = await service.nextBatch();
      expect(result.workers.single.distanceMeters, isNull);
      expect(result.locationMessage, contains('no confirmed nearby distance'));
      expect(resolver.calls, isEmpty);
    },
  );

  test('GPS permission denial falls back to saved address', () async {
    location.denied = true;
    source.pages.add([worker('a', address: 'Brgy. Nearby, Exampletown')]);
    final result = await service.nextBatch(useCurrentLocation: true);
    expect(result.workers.single.isNearby, isTrue);
    expect(
      result.locationMessage,
      contains('Could not update current location'),
    );
  });

  test(
    'GPS selection changes the origin without changing stored profile data',
    () async {
      source.pages.add([
        worker('a', address: 'Brgy. Nearby, Exampletown'),
        worker('b', address: 'Brgy. Far, Exampletown'),
      ]);
      expect((await service.nextBatch()).workers.single.id, 'a');
      expect(
        (await service.nextBatch(useCurrentLocation: true)).workers.single.id,
        'b',
      );
      expect(
        source.profile!['address'],
        '123 Client Street, Brgy. Client, Exampletown, Province',
      );
    },
  );

  test(
    'missing and invalid worker coordinates never invent distances',
    () async {
      resolver.coordinates['Brgy. Invalid, Exampletown'] = const JobCoordinate(
        latitude: 91,
        longitude: 120,
      );
      source.pages.add([
        worker('a'),
        worker('b', address: 'Brgy. Invalid, Exampletown'),
        worker('c', address: 'Brgy. Offline, Exampletown'),
      ]);
      final result = await service.nextBatch();
      expect(result.workers, hasLength(3));
      expect(
        result.workers.every((w) => w.distanceMeters == null && !w.isNearby),
        isTrue,
      );
    },
  );

  test(
    'failed client geocoding returns suggestions; failed Firestore fetch is surfaced',
    () async {
      resolver.coordinates.clear();
      source.pages.add([worker('a')]);
      expect((await service.nextBatch()).workers.single.isNearby, isFalse);
      final other = WorkerDiscoveryService(
        clientId: 'client',
        source: source,
        resolver: resolver,
      );
      source.fail = true;
      await expectLater(other.nextBatch(), throwsStateError);
    },
  );

  test(
    'messaging queries the exact pair and returns existing conversation without creating one',
    () async {
      source.existing = const WorkerConversation('client_worker', {});
      expect((await service.conversationFor('worker'))!.id, 'client_worker');
      expect(source.requestedClient, 'client');
      expect(source.requestedWorker, 'worker');
      source.existing = null;
      expect(await service.conversationFor('other'), isNull);
    },
  );

  test(
    'matching conversations reuses canonical chat and supports legacy IDs safely',
    () {
      const data = {
        'clientId': 'client',
        'workerId': 'worker',
        'participantIds': ['client', 'worker'],
      };
      const legacy = WorkerConversation('old-request', data);
      const canonical = WorkerConversation('client_worker', data);
      expect(
        matchingWorkerConversation([legacy, canonical], 'client', 'worker')!.id,
        'client_worker',
      );
      expect(
        matchingWorkerConversation([legacy], 'client', 'worker')!.id,
        'old-request',
      );
      expect(
        matchingWorkerConversation([legacy], 'client', 'wrong-worker'),
        isNull,
      );
      expect(
        matchingWorkerConversation(
          [
            const WorkerConversation('bad', {
              'clientId': 'client',
              'workerId': 'worker',
              'participantIds': ['other', 'worker'],
            }),
          ],
          'client',
          'worker',
        ),
        isNull,
      );
    },
  );
}
