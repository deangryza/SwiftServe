import 'package:flutter/material.dart';

import '../widgets_worker/animated_page.dart';
import '../widgets_worker/primary_button.dart';
import '../widgets_worker/professional_profile_form.dart';
import 'verification_screen.dart';

class ProfessionalProfileScreen extends StatefulWidget {
  const ProfessionalProfileScreen({super.key});

  @override
  State<ProfessionalProfileScreen> createState() => _S();
}

class _S extends State<ProfessionalProfileScreen> {
  String cat = 'Select service';
  String exp = 'Select experience';

  final skills = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AnimatedPage(
      child: Scaffold(
        appBar: AppBar(title: const Text('Professional Profile')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Tell clients about your skills',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 20),

            ProfessionalProfileForm(
              category: cat,
              experience: exp,
              onCategory: (v) {
                setState(() {
                  cat = v!;
                });
              },
              onExperience: (v) {
                setState(() {
                  exp = v!;
                });
              },
              skills: skills,
            ),

            const SizedBox(height: 18),

            const Text(
              'Weekly Availability',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),

            SwitchListTile(
              value: true,
              onChanged: (_) {},
              title: const Text('Available for new jobs'),
            ),

            const SizedBox(height: 15),

            PrimaryButton(
              text: 'Continue',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VerificationScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
