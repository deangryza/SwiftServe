import 'package:flutter/material.dart';

import '../../widgets/legacy/animated_page.dart';
import '../../widgets/legacy/history_job_card.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedPage(
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text(
                'History',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),

              const Text('Earnings & payments'),

              const SizedBox(height: 15),

              const HistoryJobCard(
                service: 'Math Tutoring',
                date: 'Oct 15',
                amount: '₱200',
              ),

              const HistoryJobCard(
                service: 'Pet Sitting',
                date: 'Oct 12',
                amount: '₱350',
              ),

              const HistoryJobCard(
                service: 'Math Tutoring',
                date: 'Oct 09',
                amount: '₱200',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
