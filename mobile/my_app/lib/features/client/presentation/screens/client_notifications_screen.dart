import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/action_confirmation_dialog.dart';
import '../../../../shared/models/service_request.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/utils/role_context.dart';
import '../../../../shared/widgets/role_notification_feed.dart';
import '../../../../shared/repositories/profile_repository.dart';
import '../../../worker/presentation/screens/worker_verification_screen.dart';
import '../../../../shared/screens/reviews_screen.dart';
import '../../../../shared/widgets/notification_swipe_actions.dart';

import '../../../../shared/services/client_theme_controller.dart';
import 'client_booking_flow.dart';

const _unreadYellow = AppTheme.yellow;
const _cream = Color(0xFFFFFFFF);
const _ink = AppTheme.ink;

Future<void> _deleteClientNotification(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> notification,
) async {
  final confirmed = await showActionConfirmation(
    context,
    title: 'Delete notification?',
    message:
        'Are you sure you want to delete this notification? This action cannot be undone.',
    confirmLabel: 'Delete',
    icon: Icons.delete_outline_rounded,
  );
  if (!confirmed) return;
  try {
    await notification.reference.delete();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Notification deleted.')));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not delete notification: $error')),
    );
  }
}

Future<void> _openClientNotification(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> notification,
) async {
  final data = notification.data();
  final requestId = data['requestId']?.toString();
  final type = data['type']?.toString();
  try {
    if (isVerificationNotification(data)) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Please sign in again.');
      final profile = await ProfileRepository().watch(uid).first;
      if (profile == null) throw StateError('Your profile is unavailable.');
      await notification.reference.update({'read': true});
      if (!context.mounted) return;
      Navigator.push(
        context,
        clientPageRoute(WorkerVerificationScreen(profile: profile)),
      );
      return;
    }
    if (type == 'reviewReceived' ||
        (type == null && data['title'] == 'New review received')) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        throw StateError('Please sign in again to view this review.');
      }
      await notification.reference.update({'read': true});
      if (!context.mounted) return;
      Navigator.push(
        context,
        clientPageRoute(
          ReviewsScreen(userId: uid, reviewsFor: ReviewsFor.client),
        ),
      );
      return;
    }
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
    final request = ServiceRequest.fromDocument(requestDocument);
    final destination =
        type == 'workerApplication' ||
            (type == null && request.workerId == null)
        ? ClientWorkersFoundScreen(requestId: requestId)
        : ClientBookingDetailsScreen(
            requestId: requestId,
            workerId: request.workerId!,
          );
    await notification.reference.update({'read': true});
    if (!context.mounted) return;
    Navigator.push(context, clientPageRoute(destination));
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
    final muted = dark ? const Color(0xFFB8B8B8) : AppTheme.muted;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: text,
        leading: IconButton(
          key: const ValueKey('notifications-back'),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Notifications'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: uid == null
                ? Center(
                    child: Text(
                      'Please sign in again.',
                      style: TextStyle(color: text),
                    ),
                  )
                : RoleNotificationFeed(
                    uid: uid,
                    role: UserRole.client,
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
                        return const Center(child: CircularProgressIndicator());
                      }
                      final notifications = snapshot.data!;
                      if (notifications.isEmpty) {
                        return Center(
                          child: Text(
                            'No notifications yet.',
                            style: TextStyle(color: muted),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                        itemCount: notifications.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final notification = notifications[index];
                          final data = notification.data();
                          final opened = data['read'] == true;
                          return NotificationSwipeActions(
                            key: ValueKey(
                              'client-notification-${notification.id}',
                            ),
                            actionKeyPrefix:
                                'client-notification-${notification.id}',
                            onViewDetails: () =>
                                _openClientNotification(context, notification),
                            onDelete: () => _deleteClientNotification(
                              context,
                              notification,
                            ),
                            child: _NotificationCard(
                              title: (data['title'] ?? 'Update').toString(),
                              body: (data['body'] ?? '').toString(),
                              opened: opened,
                              surface: surface,
                              text: text,
                              muted: muted,
                              onTap: () => _openClientNotification(
                                context,
                                notification,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
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
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: Theme.of(context).dividerColor),
    ),
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
