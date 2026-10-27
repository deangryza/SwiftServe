import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:my_app/shared/models/job_location.dart';
import 'package:my_app/shared/repositories/service_request_repository.dart';
import 'package:my_app/shared/services/device_location_service.dart';
import 'package:my_app/shared/services/rider_location_service.dart';

const coordinate = JobCoordinate(latitude: 14.84, longitude: 120.81);

void main() {
  late GeolocatorPlatform originalPlatform;
  late _LocationPlatform platform;
  late _LocationService locations;
  late _Repository repository;
  late RiderLocationPublisher publisher;

  setUp(() {
    originalPlatform = GeolocatorPlatform.instance;
    platform = _LocationPlatform();
    GeolocatorPlatform.instance = platform;
    locations = _LocationService();
    repository = _Repository();
    publisher = RiderLocationPublisher(
      requestId: 'errand-1',
      repository: repository,
      locationService: locations,
      minInterval: Duration.zero,
    );
  });

  tearDown(() async {
    platform.cancelGate?.complete();
    await publisher.stop();
    for (final controller in platform.controllers) {
      await controller.close();
    }
    GeolocatorPlatform.instance = originalPlatform;
  });

  test(
    'stop during GPS startup prevents later subscription and writes',
    () async {
      final gps = Completer<JobCoordinate>();
      locations.responses.add(gps.future);
      final starting = publisher.start();
      await _flush();
      await publisher.stop();
      gps.complete(coordinate);
      await starting;

      expect(publisher.isRunning, isFalse);
      expect(platform.listenCount, 0);
      expect(repository.positions, isEmpty);
    },
  );

  test('overlapping starts share one lookup and one subscription', () async {
    final gps = Completer<JobCoordinate>();
    locations.responses.add(gps.future);
    final first = publisher.start();
    final second = publisher.start();
    await _flush();
    gps.complete(coordinate);
    await Future.wait([first, second]);
    await publisher.start();

    expect(locations.calls, 1);
    expect(platform.listenCount, 1);
    expect(platform.activeCount, 1);
    expect(repository.positions, hasLength(1));
  });

  test('a cancelled old lookup cannot replace a resumed run', () async {
    final oldGps = Completer<JobCoordinate>();
    locations.responses.add(oldGps.future);
    final oldStart = publisher.start();
    await _flush();
    await publisher.stop();
    await publisher.start();
    oldGps.complete(coordinate);
    await oldStart;

    expect(publisher.isRunning, isTrue);
    expect(platform.listenCount, 1);
    expect(platform.activeCount, 1);
    expect(repository.positions, hasLength(1));
  });

  test(
    'repeated stops and resume wait for asynchronous cancellation',
    () async {
      await publisher.start();
      platform.cancelGate = Completer<void>();
      final stopping = publisher.stop();
      final stoppedAgain = publisher.stop();
      final resumed = publisher.start();
      await _flush();
      expect(publisher.isRunning, isFalse);
      expect(platform.listenCount, 1);

      platform.cancelGate!.complete();
      platform.cancelGate = null;
      await Future.wait([stopping, stoppedAgain, resumed]);
      expect(publisher.isRunning, isTrue);
      expect(platform.listenCount, 2);
      expect(platform.cancelCount, 1);
      expect(platform.activeCount, 1);
    },
  );

  test('stop during listen cancels the newly created subscription', () async {
    Future<void>? stopping;
    platform.onListen = () => stopping = publisher.stop();
    await publisher.start();
    await stopping;

    expect(publisher.isRunning, isFalse);
    expect(platform.activeCount, 0);
    expect(platform.cancelCount, 1);
    expect(repository.positions, isEmpty);

    platform.onListen = null;
    await publisher.start();
    expect(platform.activeCount, 1);
  });

  test('normal tracking publishes updates and stops delivering them', () async {
    await publisher.start();
    platform.controllers.single.add(_position());
    await _flush();
    expect(repository.positions, hasLength(2));
    expect(repository.positions.last.latitude, 14.85);
    await publisher.stop();
    platform.controllers.single.add(_position());
    await _flush();
    expect(platform.activeCount, 0);
    expect(repository.positions, hasLength(2));
  });

  test('startup failure can be retried', () async {
    final gps = Completer<JobCoordinate>();
    locations.responses.add(gps.future);
    final starting = publisher.start();
    final expectation = expectLater(
      starting,
      throwsA(isA<DeviceLocationException>()),
    );
    gps.completeError(
      const DeviceLocationException(DeviceLocationFailure.permissionDenied),
    );
    await expectation;
    await publisher.start();
    expect(publisher.isRunning, isTrue);
    expect(platform.listenCount, 1);
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _LocationService extends DeviceLocationService {
  final responses = <Future<JobCoordinate>>[];
  int calls = 0;

  @override
  Future<JobCoordinate> currentPosition() {
    calls++;
    return responses.isEmpty ? Future.value(coordinate) : responses.removeAt(0);
  }
}

class _Repository extends Fake implements ServiceRequestRepository {
  final positions = <JobCoordinate>[];

  @override
  Future<void> publishRiderLocation({
    required String requestId,
    required JobCoordinate position,
    double? heading,
    double? speed,
  }) async {
    expect(requestId, 'errand-1');
    positions.add(position);
  }
}

class _LocationPlatform extends GeolocatorPlatform {
  final controllers = <StreamController<Position>>[];
  int listenCount = 0;
  int activeCount = 0;
  int cancelCount = 0;
  Completer<void>? cancelGate;
  void Function()? onListen;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    final controller = StreamController<Position>(
      onListen: () {
        listenCount++;
        activeCount++;
        onListen?.call();
      },
      onCancel: () async {
        cancelCount++;
        await cancelGate?.future;
        activeCount--;
      },
    );
    controllers.add(controller);
    return controller.stream;
  }
}

Position _position() => Position(
  latitude: 14.85,
  longitude: 120.82,
  timestamp: DateTime(2026, 10, 23),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 90,
  headingAccuracy: 0,
  speed: 2,
  speedAccuracy: 0,
);
