import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
                      leading: const Icon(Icons.notifications_outlined),
                      title: Text((data['title'] ?? 'Update').toString()),
                      subtitle: Text((data['body'] ?? '').toString()),
                      onTap: () => document.reference.update({'read': true}),
                    );
                  }).toList(),
                );
              },
            ),
    );
  }
}
