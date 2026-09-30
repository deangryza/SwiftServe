import 'package:flutter/material.dart';

import '../../widgets/legacy/animated_page.dart';
import '../../widgets/legacy/primary_button.dart';
import '../../widgets/legacy/job_summary_card.dart';
import 'booking_accepted_screen.dart';

class JobDetailsScreen extends StatelessWidget {
  const JobDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedPage(
      child: Scaffold(
        appBar: AppBar(title: const Text('Job Details')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'House Cleaning',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 15),

            const JobSummaryCard(
              service: 'House Cleaning',
              client: 'Shrek',
              location: 'Makati City',
              schedule: 'Today • 2:00 PM',
              price: '₱900',
            ),

            const SizedBox(height: 12),

            const Text(
              'Service Description',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 7),

            const Text(
              'Please review the job details before accepting this request.',
            ),

            const SizedBox(height: 22),

            PrimaryButton(
              text: 'Accept Job',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BookingAcceptedScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
