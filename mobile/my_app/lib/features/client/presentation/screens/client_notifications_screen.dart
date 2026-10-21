import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/services/client_theme_controller.dart';
import 'client_booking_flow.dart';

const _headerYellow = Color(0xFFFFC72C);
const _unreadYellow = Color(0xFFFFD14E);
const _cream = Color(0xFFFFF9E9);
const _ink = Color(0xFF242424);

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
      clientPageRoute(ClientWorkersFoundScreen(requestId: requestId)),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : _cream;
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF3F3F3) : _ink;
    final muted = dark ? const Color(0xFFB8B8B8) : const Color(0xFF737373);

    return Scaffold(
      backgroundColor: _headerYellow,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                SizedBox(
                  height: 112,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 28, 18, 18),
                    child: Row(
                      children: [
                        Material(
                          color: const Color(0xFFFFF7D9),
                          shape: const CircleBorder(),
                          child: IconButton(
                            key: const ValueKey('notifications-back'),
                            onPressed: () => Navigator.pop(context),
                            constraints: const BoxConstraints.tightFor(
                              width: 38,
                              height: 38,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.arrow_back,
                              color: _ink,
                              size: 19,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Notifications',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(48),
                      ),
                    ),
                    child: uid == null
                        ? Center(
                            child: Text(
                              'Please sign in again.',
                              style: TextStyle(color: text),
                            ),
                          )
                        : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: FirebaseFirestore.instance
                                .collection('notifications')
                                .where('recipientId', isEqualTo: uid)
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      'Could not load notifications:\n'
                                      '${snapshot.error}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: text),
                                    ),
                                  ),
                                );
                              }
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              final notifications = snapshot.data!.docs.toList()
                                ..sort((left, right) {
                                  final leftTime =
                                      left.data()['createdAt'] as Timestamp?;
                                  final rightTime =
                                      right.data()['createdAt'] as Timestamp?;
                                  return (rightTime?.millisecondsSinceEpoch ??
                                          0)
                                      .compareTo(
                                        leftTime?.millisecondsSinceEpoch ?? 0,
                                      );
                                });
                              if (notifications.isEmpty) {
                                return Center(
                                  child: Text(
                                    'No notifications yet.',
                                    style: TextStyle(color: muted),
                                  ),
                                );
                              }
                              return ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  32,
                                  18,
                                  28,
                                ),
                                itemCount: notifications.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final notification = notifications[index];
                                  final data = notification.data();
                                  final opened = data['read'] == true;
                                  return _NotificationCard(
                                    key: ValueKey(
                                      'client-notification-${notification.id}',
                                    ),
                                    title: (data['title'] ?? 'Update')
                                        .toString(),
                                    body: (data['body'] ?? '').toString(),
                                    opened: opened,
                                    surface: surface,
                                    text: text,
                                    muted: muted,
                                    onTap: () => _openClientNotification(
                                      context,
                                      notification,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    super.key,
    required this.title,
    required this.body,
    required this.opened,
    required this.surface,
    required this.text,
    required this.muted,
    required this.onTap,
  });

  final String title;
  final String body;
  final bool opened;
  final Color surface;
  final Color text;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: surface,
    elevation: 3,
    shadowColor: Colors.black38,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 94),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 38,
                child: Icon(
                  opened
                      ? Icons.notifications_none_rounded
                      : Icons.notifications_rounded,
                  color: opened ? muted : _unreadYellow,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 11, height: 1.2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: text, size: 30),
            ],
          ),
        ),
      ),
    ),
  );
}
