import '../models/discovered_worker.dart';
import '../models/job_location.dart';
import '../repositories/worker_discovery_repository.dart';
import '../utils/job_location_utils.dart';
import '../utils/public_profile_location.dart';
import 'device_location_service.dart';
import 'job_geocoding_service.dart';

class WorkerRecommendations {
  const WorkerRecommendations(this.workers, this.locationMessage);
  final List<DiscoveredWorker> workers;
  final String locationMessage;
}

class WorkerDiscoveryService {
  WorkerDiscoveryService({
    required this.clientId,
    required WorkerDiscoverySource source,
    JobAddressResolver? resolver,
    DeviceLocationService location = const DeviceLocationService(),
  }) : _source = source,
       _resolver = resolver,
       _location = location;

  final String clientId;
  final WorkerDiscoverySource _source;
  JobAddressResolver? _resolver;
  final DeviceLocationService _location;
  final _pool = <String, DiscoveredWorker>{};
  final _positions = <String, JobCoordinate?>{};
  final _addressCache = <String, JobCoordinate>{};
  final _pendingAddresses = <String, Future<JobCoordinate?>>{};
  final _seen = <String>{};
  bool _hasMore = true;
  JobCoordinate? _currentPosition;

  bool _valid(JobCoordinate point) =>
      point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude.abs() <= 90 &&
      point.longitude.abs() <= 180;

  Future<JobCoordinate?> _resolve(String address) {
    final query = address.trim();
    if (query.isEmpty) return Future.value(null);
    if (_addressCache.containsKey(query)) {
      return Future.value(_addressCache[query]);
    }
    return _pendingAddresses.putIfAbsent(query, () async {
      try {
        final resolved = await (_resolver ??= JobGeocodingService())
            .search(query)
            .timeout(const Duration(seconds: 8));
        if (!_valid(resolved.position)) return null;
        return _addressCache[query] = resolved.position;
      } catch (_) {
        return null;
      }
    });
  }

  Future<WorkerRecommendations> nextBatch({
    bool useCurrentLocation = false,
  }) async {
    _pendingAddresses.clear();
    // Re-read the directory once all discovered workers have been shown.
    if (!_hasMore && _pool.keys.every(_seen.contains)) {
      _source.restart();
      _pool.clear();
      _positions.clear();
      _hasMore = true;
    }
    String? warning;
    if (useCurrentLocation) {
      try {
        final position = await _location.currentPosition();
        if (!_valid(position)) throw StateError('Invalid location');
        _currentPosition = position;
        _seen.clear();
      } catch (_) {
        warning =
            'Could not update current location. Using the last usable location or your saved address when possible. ';
      }
    }
    var origin = _currentPosition;
    var locationMessage =
        'Distances from your current location are approximate.';
    if (origin == null) {
      try {
        final profile = await _source.clientProfile(clientId);
        origin = await _resolve(
          PublicProfileLocation.fromAddress(profile?['address']).label,
        );
      } catch (_) {
        // Worker discovery can still provide suggestions if the address fails.
      }
      locationMessage = origin == null
          ? 'Your location is unavailable. Showing suggestions with no confirmed nearby distance.'
          : 'Approximate distances between your saved area and worker areas.';
    }
    final newlyLoaded = <String>{};
    if (_hasMore) {
      final page = await _source.nextWorkers();
      _hasMore = page.hasMore;
      for (final worker in page.workers) {
        if (worker.eligibleFor(clientId)) {
          if (_pool[worker.id] == null ||
              PublicProfileLocation.fromProfile(_pool[worker.id]!.data).label !=
                  PublicProfileLocation.fromProfile(worker.data).label) {
            _positions.remove(worker.id);
          }
          _pool[worker.id] = worker;
          newlyLoaded.add(worker.id);
        } else {
          _pool.remove(worker.id);
          _positions.remove(worker.id);
        }
      }
    }
    // Bound work per refresh. Retry failed lookups after newly loaded profiles.
    final unresolved =
        _pool.values.where((worker) => _positions[worker.id] == null).toList()
          ..sort(
            (a, b) => (newlyLoaded.contains(b.id) ? 1 : 0).compareTo(
              newlyLoaded.contains(a.id) ? 1 : 0,
            ),
          );
    final toResolve = unresolved
        .take(FirestoreWorkerDiscoverySource.pageSize)
        .toList();
    var next = 0;
    Future<void> resolveWorkers() async {
      while (next < toResolve.length) {
        final worker = toResolve[next++];
        _positions[worker.id] = await _resolve(
          PublicProfileLocation.fromProfile(worker.data).label,
        );
      }
    }

    if (origin != null) {
      await Future.wait(List.generate(4, (_) => resolveWorkers()));
    }
    final located = [
      for (final worker in _pool.values)
        DiscoveredWorker(
          id: worker.id,
          data: worker.data,
          distanceMeters: origin == null || _positions[worker.id] == null
              ? null
              : distanceMetersBetween(origin, _positions[worker.id]!),
        ),
    ];
    return WorkerRecommendations(
      nextWorkerRecommendations(
        workers: located,
        clientId: clientId,
        seenIds: _seen,
      ),
      '${warning ?? ''}$locationMessage',
    );
  }

  Future<WorkerConversation?> conversationFor(String workerId) =>
      _source.conversation(clientId, workerId);
}
