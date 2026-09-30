import 'package:flutter/material.dart';
import '../../widgets/legacy/animated_page.dart';
import '../../widgets/legacy/notification_tile.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedPage(
      child: Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            const NotificationTile(
              title: 'New Job Offer',
              body: 'A new House Cleaning request is available.',
              icon: Icons.work_outline,
            ),

            const NotificationTile(
              title: 'Booking Accepted',
              body: 'Your Math Tutoring booking was accepted.',
              icon: Icons.check_circle_outline,
            ),

            const NotificationTile(
              title: 'Verification Update',
              body: 'Your identity documents are under review.',
              icon: Icons.verified_user_outlined,
            ),

            const NotificationTile(
              title: 'New Message',
              body: 'Shrek sent you a message.',
              icon: Icons.chat_bubble_outline,
            ),
          ],
        ),
      ),
    );
  }
}
