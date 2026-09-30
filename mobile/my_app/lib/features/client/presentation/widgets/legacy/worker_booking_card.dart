import 'package:flutter/material.dart';

class WorkerBookingCard extends StatelessWidget {
  const WorkerBookingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8E8E8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),

      child: Row(
        children: [
          /// Avatar
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFFEAF2FF),
            child: const Text(
              "ZR",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Color(0xFF356AE6),
              ),
            ),
          ),

          const SizedBox(width: 15),

          /// Worker Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Zoro R.",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 5),

                Row(
                  children: const [
                    Text(
                      "Tutoring",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),

                    SizedBox(width: 8),

                    Icon(Icons.star, color: Colors.amber, size: 18),

                    SizedBox(width: 3),

                    Text(
                      "4.9",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),

          /// Offered Price
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "Offered",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
              ),

              const SizedBox(height: 4),

              const Text(
                "₱200",
                style: TextStyle(
                  color: Color(0xFF2F80ED),
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
