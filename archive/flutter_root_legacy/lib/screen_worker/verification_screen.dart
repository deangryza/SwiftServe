import 'package:flutter/material.dart';

import '../widgets_worker/animated_page.dart';
import '../widgets_worker/primary_button.dart';
import '../widgets_worker/verification_upload_card.dart';
import 'verification_status_screen.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  bool idUploaded = false;
  bool certificateUploaded = false;
  bool proofUploaded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedPage(
      child: Scaffold(
        appBar: AppBar(title: const Text('Worker Verification')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Verify your account',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 8),

            const Text('Submit documents so clients can trust your profile.'),

            const SizedBox(height: 20),

            VerificationUploadCard(
              title: 'Government ID',
              subtitle: 'Front and back of a valid ID',
              icon: Icons.badge_outlined,
              uploaded: idUploaded,
              onUpload: () {
                setState(() {
                  idUploaded = true;
                });
              },
            ),

            VerificationUploadCard(
              title: 'Certificates',
              subtitle: 'Upload relevant certificates',
              icon: Icons.workspace_premium_outlined,
              uploaded: certificateUploaded,
              onUpload: () {
                setState(() {
                  certificateUploaded = true;
                });
              },
            ),

            VerificationUploadCard(
              title: 'Proof of Work',
              subtitle: 'Portfolio or previous work',
              icon: Icons.photo_library_outlined,
              uploaded: proofUploaded,
              onUpload: () {
                setState(() {
                  proofUploaded = true;
                });
              },
            ),

            const SizedBox(height: 15),

            PrimaryButton(
              text: 'Submit for Verification',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const VerificationStatusScreen(),
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
