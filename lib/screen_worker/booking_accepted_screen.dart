import 'package:flutter/material.dart';

import '../widgets_worker/animated_page.dart';
import '../widgets_worker/accepted_booking_card.dart';
import 'ongoing_task_screen.dart';

class BookingAcceptedScreen extends StatelessWidget {
  const BookingAcceptedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedPage(
      child: Scaffold(
        appBar: AppBar(title: const Text('Booking Accepted')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const AcceptedBookingCard(),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OngoingTaskScreen()),
                );
              },
              child: const Text('View Ongoing Task'),
            ),
          ],
        ),
      ),
    );
  }
}
