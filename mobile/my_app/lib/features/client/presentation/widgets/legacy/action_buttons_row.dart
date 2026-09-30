import 'package:flutter/material.dart';

class ActionButtonsRow extends StatelessWidget {
  const ActionButtonsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 55,
            child: OutlinedButton.icon(
              onPressed: () {
                // Tawag mamaya
              },
              icon: const Icon(Icons.call),
              label: const Text("Call"),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2F80ED),
                side: const BorderSide(color: Color(0xFF2F80ED)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(width: 15),

        Expanded(
          child: SizedBox(
            height: 55,
            child: ElevatedButton.icon(
              onPressed: () {
                // Chat mamaya
              },
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text("Message"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2F80ED),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
