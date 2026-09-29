import 'package:flutter/material.dart';

class LoginFormWidget extends StatelessWidget {
  final TextEditingController email;
  final TextEditingController password;
  final bool obscure;
  final VoidCallback togglePassword;

  const LoginFormWidget({
    super.key,
    required this.email,
    required this.password,
    required this.obscure,
    required this.togglePassword,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Email'),

        const SizedBox(height: 7),

        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Enter your email',
          ),
        ),

        const SizedBox(height: 16),

        const Text('Password'),

        const SizedBox(height: 7),

        TextField(
          controller: password,
          obscureText: obscure,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'Enter your password',
            suffixIcon: IconButton(
              onPressed: togglePassword,
              icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
            ),
          ),
        ),
      ],
    );
  }
}
