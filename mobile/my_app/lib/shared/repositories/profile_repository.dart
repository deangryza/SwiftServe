import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';

class ProfileRepository {
  ProfileRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<AppUser?> watch(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .snapshots()
      .map(
        (document) => document.exists
            ? AppUser.fromMap(document.id, document.data()!)
            : null,
      );
}
