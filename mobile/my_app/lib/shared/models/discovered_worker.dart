import '../utils/job_location_utils.dart';

const nearbyWorkerRadiusMeters = 10000.0;

class DiscoveredWorker {
  const DiscoveredWorker({
    required this.id,
    required this.data,
    this.distanceMeters,
  });

  final String id;
  final Map<String, dynamic> data;
  final double? distanceMeters;

  String get name => (data['fullName'] ?? 'Service provider').toString();
  bool get hasDistance =>
      distanceMeters != null &&
      distanceMeters!.isFinite &&
      distanceMeters! >= 0;
  bool get isNearby =>
      hasDistance && distanceMeters! <= nearbyWorkerRadiusMeters;

  bool eligibleFor(String clientId) =>
      id.isNotEmpty &&
      id != clientId &&
      data['verificationStatus'] == 'verified' &&
      (data['role'] == null || data['role'] == 'worker') &&
      (data['workerId'] == null || data['workerId'] == id);

  String get distanceLabel => !hasDistance
      ? 'Distance unavailable'
      : formatDistance(distanceMeters!, approximate: true);
}

/// Nearest unseen workers first; suggestions are a separate batch. Only repeat
/// once every eligible worker in the discovered pool has been shown.
List<DiscoveredWorker> nextWorkerRecommendations({
  required Iterable<DiscoveredWorker> workers,
  required String clientId,
  required Set<String> seenIds,
}) {
  final unique = <String, DiscoveredWorker>{
    for (final worker in workers)
      if (worker.eligibleFor(clientId)) worker.id: worker,
  }.values.toList();
  unique.sort((a, b) {
    final distance = (a.hasDistance ? a.distanceMeters! : double.infinity)
        .compareTo(b.hasDistance ? b.distanceMeters! : double.infinity);
    return distance == 0 ? a.id.compareTo(b.id) : distance;
  });
  var unseen = unique.where((worker) => !seenIds.contains(worker.id)).toList();
  if (unseen.isEmpty && unique.isNotEmpty) {
    seenIds.clear();
    unseen = unique;
  }
  final nearby = unseen.where((worker) => worker.isNearby).toList();
  final batch = (nearby.isNotEmpty ? nearby : unseen).take(10).toList();
  seenIds.addAll(batch.map((worker) => worker.id));
  return batch;
}
