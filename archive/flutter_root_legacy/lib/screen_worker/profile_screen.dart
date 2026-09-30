import 'package:flutter/material.dart';

import '../widgets_worker/animated_page.dart';
import '../widgets_worker/profile_header.dart';
import 'professional_profile_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedPage(
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text(
                'Profile',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),

              const SizedBox(height: 12),

              ProfileHeader(
                onEdit: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProfessionalProfileScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 12),

              const Card(
                child: ListTile(
                  title: Text('Service Categories'),
                  subtitle: Text('Electrical • Plumbing'),
                ),
              ),

              const Card(
                child: ListTile(
                  title: Text('Achievements & Awards'),
                  subtitle: Text('TESDA NCII • SwiftServe Top Pro 2023'),
                ),
              ),

              const Card(
                child: ListTile(
                  title: Text('Reviews'),
                  subtitle: Text('4.9 ★★★★★ • 120 reviews'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
