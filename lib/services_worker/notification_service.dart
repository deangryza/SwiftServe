import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  final FirebaseMessaging messaging = FirebaseMessaging.instance;

  Future<void> initialize() async {
    await messaging.requestPermission();
    await messaging.getToken();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchNotifications(
    String userId,
  ) {
    return firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .snapshots();
  }
}
