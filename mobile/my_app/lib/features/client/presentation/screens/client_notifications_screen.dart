import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/models/service_request.dart';
import 'client_request_details_screen.dart';

Future<void> _openClientNotification(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> notification,
) async {
  final requestId = notification.data()['requestId']?.toString();
  try {
    await notification.reference.update({'read': true});
    if (requestId == null || requestId.isEmpty) {
      throw StateError('This notification has no linked request.');
    }
    final requestDocument = await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .get();
    if (!requestDocument.exists) {
      throw StateError('This service request is no longer available.');
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClientRequestDetailsScreen(
          request: ServiceRequest.fromDocument(requestDocument),
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open notification: $error')),
    );
  }
}

class ClientNotificationsScreen extends StatelessWidget {
  const ClientNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: uid == null
          ? const Center(child: Text('Please sign in again.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('recipientId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final notifications = snapshot.data!.docs.toList()
                  ..sort((a, b) {
                    final left = a.data()['createdAt'] as Timestamp?;
                    final right = b.data()['createdAt'] as Timestamp?;
                    return (right?.millisecondsSinceEpoch ?? 0).compareTo(
                      left?.millisecondsSinceEpoch ?? 0,
                    );
                  });
                if (notifications.isEmpty) {
                  return const Center(child: Text('No notifications.'));
                }
                return ListView(
                  children: notifications.map((document) {
                    final data = document.data();
                    return ListTile(
                      leading: Icon(
                        data['read'] == true
                            ? Icons.notifications_outlined
                            : Icons.notifications_active,
                      ),
                      title: Text((data['title'] ?? 'Update').toString()),
                      subtitle: Text((data['body'] ?? '').toString()),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openClientNotification(context, document),
                    );
                  }).toList(),
                );
              },
            ),
    );
  }
}
