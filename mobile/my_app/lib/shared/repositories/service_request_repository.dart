import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/service_request.dart';

class ServiceRequestRepository {
  ServiceRequestRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<ServiceRequest>> watchAvailable() => _firestore
      .collection('service_requests')
      .where('status', isEqualTo: ServiceRequestStatus.pending.name)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(ServiceRequest.fromDocument)
            .toList(growable: false),
      );

  Stream<List<ServiceRequest>> watchWorkerJobs(String workerId) => _firestore
      .collection('service_requests')
      .where('workerId', isEqualTo: workerId)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(ServiceRequest.fromDocument)
            .toList(growable: false),
      );

  Future<void> accept({
    required ServiceRequest request,
    required String workerId,
    required String workerName,
  }) async {
    final workerRef = _firestore.collection('users').doc(workerId);
    final requestRef = _firestore
        .collection('service_requests')
        .doc(request.id);
    final conversationRef = _firestore
        .collection('conversations')
        .doc(request.id);
    final notificationRef = _firestore.collection('notifications').doc();

    await _firestore.runTransaction((transaction) async {
      final worker = await transaction.get(workerRef);
      final latestRequest = await transaction.get(requestRef);
      if (worker.data()?['verificationStatus'] != 'verified') {
        throw StateError('Worker verification is required.');
      }
      if (latestRequest.data()?['status'] != 'pending' ||
          latestRequest.data()?['workerId'] != null) {
        throw StateError('This request is no longer available.');
      }
      transaction.update(requestRef, {
        'status': ServiceRequestStatus.accepted.name,
        'workerId': workerId,
        'workerName': workerName,
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(conversationRef, {
        'requestId': request.id,
        'participantIds': [request.clientId, workerId],
        'clientId': request.clientId,
        'clientName': request.clientName,
        'workerId': workerId,
        'workerName': workerName,
        'lastMessage': 'Request accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(notificationRef, {
        'recipientId': request.clientId,
        'senderId': workerId,
        'requestId': request.id,
        'title': 'Request accepted',
        'body': '$workerName accepted ${request.title}.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> transition({
    required String requestId,
    required ServiceRequestStatus from,
    required ServiceRequestStatus to,
    required String workerId,
  }) async {
    final reference = _firestore.collection('service_requests').doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final data = snapshot.data();
      if (data == null ||
          data['workerId'] != workerId ||
          data['status'] != from.name) {
        throw StateError('The request changed before this action completed.');
      }
      transaction.update(reference, {
        'status': to.name,
        '${to.name}At': FieldValue.serverTimestamp(),
      });
    });
  }
}
