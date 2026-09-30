import 'package:flutter/material.dart';

import 'accept_button.dart';
import 'decline_button.dart';

class NotificationCard extends StatelessWidget {
  const NotificationCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xffEAEAEA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// Top Row
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xffDCE9FF),

                child: const Text(
                  "ZR",
                  style: TextStyle(
                    color: Color(0xff4169E1),
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),

              const SizedBox(width: 15),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Zoro R.",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Row(
                      children: const [
                        Icon(Icons.star, color: Colors.amber, size: 18),

                        SizedBox(width: 4),

                        Text(
                          "4.9",
                          style: TextStyle(color: Colors.grey, fontSize: 15),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),

                decoration: BoxDecoration(
                  color: const Color(0xffE8F0FF),
                  borderRadius: BorderRadius.circular(30),
                ),

                child: const Text(
                  "₱200",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Color(0xff2F5BD3),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          /// Time
          Row(
            children: const [
              Icon(Icons.access_time, size: 18, color: Colors.grey),

              SizedBox(width: 6),

              Text("Today • 2:00 PM", style: TextStyle(color: Colors.grey)),
            ],
          ),

          const SizedBox(height: 15),

          /// Message
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),

            decoration: BoxDecoration(
              color: const Color(0xffF6F7FB),
              borderRadius: BorderRadius.circular(15),
            ),

            child: const Text(
              "Maybe you need a math tutor. I'm available today.",
              style: TextStyle(fontSize: 16, height: 1.4),
            ),
          ),

          const SizedBox(height: 18),

          /// Buttons
          Row(
            children: [
              Expanded(
                child: AcceptButton(
                  onPressed: () {
                    // Firebase mamaya
                  },
                ),
              ),

              const SizedBox(width: 15),

              Expanded(
                child: DeclineButton(
                  onPressed: () {
                    // Firebase mamaya
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
