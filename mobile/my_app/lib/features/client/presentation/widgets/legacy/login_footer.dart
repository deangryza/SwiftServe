import 'package:flutter/material.dart';

class LoginFooter extends StatelessWidget {
  final VoidCallback onSignUp;

  const LoginFooter({super.key, required this.onSignUp});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "Don't have an account? ",
          style: TextStyle(color: Colors.grey, fontSize: 15),
        ),
        GestureDetector(
          onTap: onSignUp,
          child: const Text(
            "Sign Up",
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}
