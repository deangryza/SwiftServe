import 'package:flutter/material.dart';

class AcceptButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const AcceptButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,

      child: ElevatedButton.icon(
        onPressed: onPressed,

        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xff16C784),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),

        icon: const Icon(Icons.check, size: 22),

        label: const Text(
          "Accept",
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
