import 'package:flutter/material.dart';

class MessageWorkerButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const MessageWorkerButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onPressed,

        icon: const Icon(
          Icons.chat_bubble_outline_rounded,
          size: 22,
          color: Colors.black87,
        ),

        label: const Text(
          "Message worker",
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),

        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFE5E5E5), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}
