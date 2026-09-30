import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/app_user.dart';

class VerificationRepository {
  VerificationRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  Stream<DocumentSnapshot<Map<String, dynamic>>> watch(String uid) =>
      _firestore.collection('worker_verifications').doc(uid).snapshots();

  Stream<VerificationStatus?> watchStatus(String uid) => watch(uid).map(
    (document) => document.exists
        ? VerificationStatus.fromWire(document.data()?['status'])
        : null,
  );

  Future<void> submit({
    required String uid,
    required String idType,
    required String idNumber,
    required File governmentId,
    required File facePhoto,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final base = _storage.ref('worker_verifications/$uid/$timestamp');
    final idReference = base.child('government_id.${_extension(governmentId)}');
    final faceReference = base.child('face_photo.${_extension(facePhoto)}');
    await Future.wait([
      idReference.putFile(governmentId),
      faceReference.putFile(facePhoto),
    ]);
    await _firestore.collection('worker_verifications').doc(uid).set({
      'workerId': uid,
      'idType': idType,
      'maskedIdNumber': _masked(idNumber),
      'governmentIdPath': idReference.fullPath,
      'facePhotoPath': faceReference.fullPath,
      'idSubmitted': true,
      'faceVerified': false,
      'status': 'pending',
      'adminNotes': '',
      'submittedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _extension(File file) {
    final segments = file.path.split('.');
    return segments.length > 1 ? segments.last.toLowerCase() : 'jpg';
  }

  String _masked(String value) {
    final trimmed = value.trim();
    final suffix = trimmed.length <= 4
        ? trimmed
        : trimmed.substring(trimmed.length - 4);
    return '********$suffix';
  }
}
