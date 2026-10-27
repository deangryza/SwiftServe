import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/discovered_worker.dart';
import 'service_request_repository.dart';

class WorkerDiscoveryPage {
  const WorkerDiscoveryPage(this.workers, {required this.hasMore});
  final List<DiscoveredWorker> workers;
  final bool hasMore;
}

class WorkerConversation {
  const WorkerConversation(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
}

WorkerConversation? matchingWorkerConversation(
  Iterable<WorkerConversation> conversations,
  String clientId,
  String workerId,
) {
  final matches = conversations.where((conversation) {
    final data = conversation.data;
    final participants = data['participantIds'];
    return data['clientId'] == clientId &&
        data['workerId'] == workerId &&
        participants is List &&
        participants.length == 2 &&
        participants.contains(clientId) &&
        participants.contains(workerId);
  }).toList();
  if (matches.isEmpty) return null;
  final canonicalId = conversationIdFor(clientId: clientId, workerId: workerId);
  for (final match in matches) {
    if (match.id == canonicalId) return match;
  }
  return matches.first; // Also support older request-id conversations.
}

abstract interface class WorkerDiscoverySource {
  void restart();
  Future<Map<String, dynamic>?> clientProfile(String clientId);
  Future<WorkerDiscoveryPage> nextWorkers();
  Future<WorkerConversation?> conversation(String clientId, String workerId);
}

class FirestoreWorkerDiscoverySource implements WorkerDiscoverySource {
  FirestoreWorkerDiscoverySource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  QueryDocumentSnapshot<Map<String, dynamic>>? _cursor;
  static const pageSize = 30;

  @override
  void restart() => _cursor = null;

  @override
  Future<Map<String, dynamic>?> clientProfile(String clientId) async =>
      (await _firestore.collection('users').doc(clientId).get()).data();

  @override
  Future<WorkerDiscoveryPage> nextWorkers() async {
    var query = _firestore
        .collection('worker_profiles')
        .where('verificationStatus', isEqualTo: 'verified')
        .limit(pageSize);
    if (_cursor != null) query = query.startAfterDocument(_cursor!);
    final snapshot = await query.get();
    if (snapshot.docs.isNotEmpty) _cursor = snapshot.docs.last;
    return WorkerDiscoveryPage([
      for (final doc in snapshot.docs)
        DiscoveredWorker(id: doc.id, data: doc.data()),
    ], hasMore: snapshot.docs.length == pageSize);
  }

  @override
  Future<WorkerConversation?> conversation(
    String clientId,
    String workerId,
  ) async {
    // This is the existing participant-scoped inbox query. No new composite
    // index or permission to read other people's conversations is needed.
    final snapshot = await _firestore
        .collection('conversations')
        .where('participantIds', arrayContains: clientId)
        .get();
    return matchingWorkerConversation(
      [for (final doc in snapshot.docs) WorkerConversation(doc.id, doc.data())],
      clientId,
      workerId,
    );
  }
}
