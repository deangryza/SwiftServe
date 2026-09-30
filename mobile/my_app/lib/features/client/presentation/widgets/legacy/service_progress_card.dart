import 'package:flutter/material.dart';

class ServiceProgressCard extends StatelessWidget {
  const ServiceProgressCard({super.key});

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
            "Service Progress",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 30),

          Row(
            children: [
              /// Accepted
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 45,
                      height: 45,
                      decoration: const BoxDecoration(
                        color: Color(0xff2F80ED),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, color: Colors.white),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      "Accepted",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),

              Container(height: 3, width: 40, color: const Color(0xff2F80ED)),

              /// In Progress
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 45,
                      height: 45,
                      decoration: const BoxDecoration(
                        color: Color(0xff2F80ED),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.engineering, color: Colors.white),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      "In Progress",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),

              Container(height: 3, width: 40, color: Colors.grey.shade300),

              /// Completed
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 45,
                      height: 45,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.flag, color: Colors.white),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      "Completed",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
