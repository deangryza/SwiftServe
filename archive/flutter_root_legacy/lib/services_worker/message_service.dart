import 'package:cloud_firestore/cloud_firestore.dart';

import 'api_service.dart';

class MessageService {
  final ApiService api = ApiService();
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String receiverId,
    required String text,
  }) {
    return api.sendMessage(conversationId, senderId, receiverId, text);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(
    String conversationId,
  ) {
    return firestore
        .collection('messages')
        .where('conversationId', isEqualTo: conversationId)
        .orderBy('createdAt')
        .snapshots();
  }
}
