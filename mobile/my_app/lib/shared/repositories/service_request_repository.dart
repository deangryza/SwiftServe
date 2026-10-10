import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/service_application.dart';
import '../models/service_request.dart';

String conversationIdFor({
  required String clientId,
  required String workerId,
}) => '${clientId}_$workerId';

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

  Stream<ServiceApplication?> watchApplication({
    required String requestId,
    required String workerId,
  }) => _firestore
      .collection('service_requests')
      .doc(requestId)
      .collection('applications')
      .doc(workerId)
      .snapshots()
      .map(
        (document) =>
            document.exists ? ServiceApplication.fromDocument(document) : null,
      );

  Stream<List<ServiceApplication>> watchApplications(String requestId) =>
      _firestore
          .collection('service_requests')
          .doc(requestId)
          .collection('applications')
          .snapshots()
          .map((snapshot) {
            final applications = snapshot.docs
                .map(ServiceApplication.fromDocument)
                .toList(growable: false);
            applications.sort((a, b) {
              final aTime = a.appliedAt;
              final bTime = b.appliedAt;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return aTime.compareTo(bTime);
            });
            return applications;
          });

  Stream<List<ServiceApplication>> watchWorkerApplications(String workerId) =>
      _firestore
          .collectionGroup('applications')
          .where('workerId', isEqualTo: workerId)
          .snapshots()
          .map((snapshot) {
            final applications = snapshot.docs
                .map(ServiceApplication.fromDocument)
                .toList(growable: false);
            applications.sort((a, b) {
              final aTime = a.appliedAt;
              final bTime = b.appliedAt;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });
            return applications;
          });

  Future<ServiceRequest?> getRequest(String requestId) async {
    final document = await _firestore
        .collection('service_requests')
        .doc(requestId)
        .get();
    return document.exists ? ServiceRequest.fromDocument(document) : null;
  }

  Future<void> apply({
    required ServiceRequest request,
    required AppUser worker,
  }) async {
    final requestRef = _firestore
        .collection('service_requests')
        .doc(request.id);
    final applicationRef = requestRef.collection('applications').doc(worker.id);
    final notificationRef = _firestore.collection('notifications').doc();

    await _firestore.runTransaction((transaction) async {
      final latestRequest = await transaction.get(requestRef);
      final existingApplication = await transaction.get(applicationRef);
      if (worker.verificationStatus != VerificationStatus.verified) {
        throw StateError('Worker verification is required.');
      }
      if (latestRequest.data()?['status'] != 'pending') {
        throw StateError('This request is no longer accepting applications.');
      }
      if (existingApplication.exists) {
        throw StateError('You already applied for this request.');
      }

      transaction.set(applicationRef, {
        'requestId': request.id,
        'clientId': request.clientId,
        'workerId': worker.id,
        'workerName': worker.fullName,
        'status': ServiceApplicationStatus.pending.name,
        'appliedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(notificationRef, {
        'recipientId': request.clientId,
        'senderId': worker.id,
        'requestId': request.id,
        'title': 'New worker application',
        'body': '${worker.fullName} applied for ${request.title}.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> acceptApplicant({
    required ServiceRequest request,
    required ServiceApplication application,
  }) async {
    final requestRef = _firestore
        .collection('service_requests')
        .doc(request.id);
    final applicationsRef = requestRef.collection('applications');
    final selectedRef = applicationsRef.doc(application.workerId);
    final conversationRef = _firestore
        .collection('conversations')
        .doc(
          conversationIdFor(
            clientId: request.clientId,
            workerId: application.workerId,
          ),
        );
    final notificationRef = _firestore.collection('notifications').doc();
    final applicationSnapshot = await applicationsRef.get();

    await _firestore.runTransaction((transaction) async {
      final latestRequest = await transaction.get(requestRef);
      final selected = await transaction.get(selectedRef);
      if (latestRequest.data()?['status'] != 'pending') {
        throw StateError('A worker has already been selected.');
      }
      if (!selected.exists ||
          selected.data()?['status'] != ServiceApplicationStatus.pending.name) {
        throw StateError('This application is no longer available.');
      }

      transaction.update(requestRef, {
        'status': ServiceRequestStatus.accepted.name,
        'workerId': application.workerId,
        'workerName': application.workerName,
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      for (final document in applicationSnapshot.docs) {
        transaction.update(document.reference, {
          'status': document.id == application.workerId
              ? ServiceApplicationStatus.accepted.name
              : ServiceApplicationStatus.rejected.name,
          'reviewedAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.set(conversationRef, {
        'requestId': request.id,
        'participantIds': [request.clientId, application.workerId],
        'clientId': request.clientId,
        'clientName': request.clientName,
        'workerId': application.workerId,
        'workerName': application.workerName,
        'lastMessage': 'Application accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      transaction.set(notificationRef, {
        'recipientId': application.workerId,
        'senderId': request.clientId,
        'requestId': request.id,
        'title': 'Application accepted',
        'body': '${request.clientName} selected you for ${request.title}.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

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
