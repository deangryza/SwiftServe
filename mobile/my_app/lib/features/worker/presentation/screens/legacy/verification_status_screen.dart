import 'package:flutter/material.dart';
import '../../widgets/legacy/animated_page.dart';
import '../../widgets/legacy/verification_timeline.dart';

class VerificationStatusScreen extends StatelessWidget {
  const VerificationStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedPage(
      child: Scaffold(
        appBar: AppBar(title: const Text('Verification Status')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 20),

            const Icon(Icons.verified_user_outlined, size: 78),

            const SizedBox(height: 12),

            const Center(
              child: Text(
                'Verification in Progress',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
              ),
            ),

            const SizedBox(height: 7),

            const Center(
              child: Text(
                'Our team is reviewing your documents.',
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 24),

            const VerificationTimeline(),
          ],
        ),
      ),
    );
  }
}
