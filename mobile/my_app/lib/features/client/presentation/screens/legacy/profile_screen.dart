import 'package:flutter/material.dart';

import '../../widgets/legacy/profile_header_card.dart';
import '../../widgets/legacy/profile_contact_card.dart';
import '../../widgets/legacy/profile_menu_tile.dart';
import '../../widgets/legacy/logout_button.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF7F8FA),

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          "Profile",
          style: TextStyle(
            color: Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_horiz, color: Colors.black),
          ),
        ],
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const ProfileHeaderCard(),

              const SizedBox(height: 20),

              const ProfileContactCard(),

              const SizedBox(height: 20),

              ProfileMenuTile(
                icon: Icons.settings_outlined,
                title: "Settings",
                onTap: () {
                  // TODO: Open Settings Screen
                },
              ),

              const SizedBox(height: 12),

              ProfileMenuTile(
                icon: Icons.privacy_tip_outlined,
                title: "Privacy Policy",
                onTap: () {
                  // TODO: Open Privacy Screen
                },
              ),

              const SizedBox(height: 12),

              ProfileMenuTile(
                icon: Icons.help_outline,
                title: "Help & Support",
                onTap: () {
                  // TODO: Open Help Screen
                },
              ),

              const SizedBox(height: 12),

              ProfileMenuTile(
                icon: Icons.info_outline,
                title: "About SwiftServe",
                onTap: () {
                  // TODO: Open About Screen
                },
              ),

              const SizedBox(height: 25),

              LogoutButton(
                onPressed: () {
                  // TODO: Implement logout functionality
                },
              ),

              const SizedBox(height: 25),
            ],
          ),
        ),
      ),

      // bottomNavigationBar: const BottomNavBar(currentIndex: 3),
    );
  }
}
