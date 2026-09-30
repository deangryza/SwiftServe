import 'package:flutter/material.dart';
import '../../widgets/legacy/animated_page.dart';
import '../../widgets/legacy/primary_button.dart';
import '../../widgets/legacy/login_form_widget.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _S();
}

class _S extends State<LoginScreen> {
  final email = TextEditingController(), password = TextEditingController();
  bool obscure = true, loading = false;
  @override
  Widget build(BuildContext c) => AnimatedPage(
    child: Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const SizedBox(height: 60),
            const Center(
              child: Text(
                'SwiftServe',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Worker Sign In',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 35),
            LoginFormWidget(
              email: email,
              password: password,
              obscure: obscure,
              togglePassword: () => setState(() => obscure = !obscure),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {},
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              text: 'Sign in',
              loading: loading,
              onPressed: () async {
                setState(() => loading = true);
                await Future.delayed(const Duration(milliseconds: 500));
                if (c.mounted) {
                  Navigator.pushReplacement(
                    c,
                    MaterialPageRoute(builder: (_) => const DashboardScreen()),
                  );
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}
