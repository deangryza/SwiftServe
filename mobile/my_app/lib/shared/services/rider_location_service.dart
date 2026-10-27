import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/job_location.dart';
import '../repositories/service_request_repository.dart';
import 'device_location_service.dart';

/// Streams the rider's position to an errand while the rider's app is open.
///
/// Writes are throttled so a moving rider costs a handful of Firestore writes
/// per minute, not one per GPS fix.
class RiderLocationPublisher {
  RiderLocationPublisher({
    required this.requestId,
    ServiceRequestRepository? repository,
    DeviceLocationService locationService = const DeviceLocationService(),
    this.minInterval = const Duration(seconds: 8),
  }) : _repository = repository ?? ServiceRequestRepository(),
       _locationService = locationService;

  final String requestId;
  final Duration minInterval;
  final ServiceRequestRepository _repository;
  final DeviceLocationService _locationService;

  StreamSubscription<Position>? _subscription;
  Future<void>? _starting;
  Future<void> _cancelling = Future<void>.value();
  int _generation = 0;
  DateTime? _lastSentAt;
  Position? _pending;
  Timer? _pendingTimer;

  bool get isRunning => _subscription != null;

  /// Starts sharing. Throws [DeviceLocationException] when location is off or
  /// permission is refused.
  Future<void> start() {
    if (isRunning) return Future<void>.value();
    return _starting ??= _start(_generation);
  }

  Future<void> _start(int generation) async {
    try {
      await _cancelling;
      if (generation != _generation) return;
      // A stopped lookup may finish later; it must not publish or subscribe.
      final first = await _locationService.currentPosition();
      await _cancelling;
      if (generation != _generation) return;

      final subscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 15,
            ),
          ).listen((position) {
            if (generation == _generation) _onPosition(position);
          }, onError: (_) {});
      // A stream can synchronously trigger stop() from its onListen callback.
      if (generation != _generation) {
        await _cancel(subscription);
        return;
      }
      _subscription = subscription;
      unawaited(_send(first, null, null));
    } catch (_) {
      // An obsolete lookup must not report an error into a resumed run.
      if (generation == _generation) rethrow;
    } finally {
      if (generation == _generation) _starting = null;
    }
  }

  Future<void> _cancel(StreamSubscription<Position>? subscription) {
    return _cancelling = Future.wait<void>([
      _cancelling,
      if (subscription != null) subscription.cancel(),
    ]).then<void>((_) {});
  }

  void _onPosition(Position position) {
    final lastSentAt = _lastSentAt;
    final now = DateTime.now();
    if (lastSentAt == null || now.difference(lastSentAt) >= minInterval) {
      _sendPosition(position);
      return;
    }
    // Keep only the newest fix and send it once the interval has passed.
    _pending = position;
    _pendingTimer ??= Timer(minInterval - now.difference(lastSentAt), () {
      _pendingTimer = null;
      final pending = _pending;
      _pending = null;
      if (pending != null && isRunning) _sendPosition(pending);
    });
  }

  void _sendPosition(Position position) => unawaited(
    _send(
      JobCoordinate(latitude: position.latitude, longitude: position.longitude),
      position.heading >= 0 ? position.heading : null,
      position.speed >= 0 ? position.speed : null,
    ),
  );

  Future<void> _send(
    JobCoordinate position,
    double? heading,
    double? speed,
  ) async {
    _lastSentAt = DateTime.now();
    try {
      await _repository.publishRiderLocation(
        requestId: requestId,
        position: position,
        heading: heading,
        speed: speed,
      );
    } catch (_) {
      // A dropped update is replaced by the next one; the client shows how
      // old the last position is.
    }
  }

  Future<void> stop() {
    _generation++;
    _starting = null;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pending = null;
    final subscription = _subscription;
    _subscription = null;
    return _cancel(subscription);
  }
}
