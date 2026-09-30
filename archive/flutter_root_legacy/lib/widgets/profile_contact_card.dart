import 'package:flutter/material.dart';

class ProfileContactCard extends StatelessWidget {
  const ProfileContactCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: const [
          _ContactTile(
            icon: Icons.email_outlined,
            title: "zoro.r@swampmail.com",
          ),

          Divider(height: 1),

          _ContactTile(icon: Icons.phone_outlined, title: "+63 912 345 6789"),

          Divider(height: 1),

          _ContactTile(icon: Icons.location_on_outlined, title: "Malolos City"),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final String title;

  const _ContactTile({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey, size: 24),

          const SizedBox(width: 18),

          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
