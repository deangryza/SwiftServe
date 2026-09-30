import 'package:flutter/material.dart';
import 'map_tracking_card.dart';

class WorkerInfoCard extends StatelessWidget {
  const WorkerInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
          /// Worker Info
          Row(
            children: [
              const CircleAvatar(
                radius: 34,
                backgroundColor: Color(0xffEAF2FF),
                child: Text(
                  "ZR",
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff3D5AFE),
                  ),
                ),
              ),

              const SizedBox(width: 15),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Zoro R.",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    SizedBox(height: 5),

                    Text(
                      "Math Tutor • Online",
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),

                    SizedBox(height: 4),

                    Row(
                      children: [
                        Icon(Icons.star, color: Colors.amber, size: 18),

                        SizedBox(width: 4),

                        Text(
                          "4.9 Rating",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text("Message"),
            ),
          ),

          const SizedBox(height: 20),

          /// Google Map Placeholder
          const MapTrackingCard(),
        ],
      ),
    );
  }
}
