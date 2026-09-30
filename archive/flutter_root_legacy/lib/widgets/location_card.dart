import 'package:flutter/material.dart';

class LocationCard extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const LocationCard({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xffF8FBFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffD6E8FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xffEAF4FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_on, color: Color(0xff1565C0)),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Enable Location",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  "Allow SwiftServe to access your location to verify your service area and provide accurate nearby assistance.",
                  style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: const Color(0xff1565C0),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
