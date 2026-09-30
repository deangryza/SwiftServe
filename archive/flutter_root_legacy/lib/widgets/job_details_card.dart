import 'package:flutter/material.dart';

class JobDetailsCard extends StatelessWidget {
  const JobDetailsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Job Details",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 25),

          _buildItem(Icons.work_outline, "Service", "Math Tutoring"),

          const Divider(height: 30),

          _buildItem(
            Icons.calendar_today_outlined,
            "Schedule",
            "July 12, 2026 • 2:00 PM",
          ),

          const Divider(height: 30),

          _buildItem(
            Icons.location_on_outlined,
            "Location",
            "Malolos, Bulacan",
          ),

          const Divider(height: 30),

          _buildItem(Icons.payments_outlined, "Budget", "₱200"),

          const Divider(height: 30),

          _buildItem(
            Icons.notes_outlined,
            "Notes",
            "Need help solving Algebra assignments.",
          ),
        ],
      ),
    );
  }

  Widget _buildItem(IconData icon, String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xff2F80ED)),

        const SizedBox(width: 15),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),

              const SizedBox(height: 5),

              Text(
                value,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
