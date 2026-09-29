import 'package:flutter/material.dart';
import '../widgets/login_textfield.dart';
import '../widgets/login_button.dart';
import '../widgets/login_footer.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool obscure = true;
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF7F8FC),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 30),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              const Text(
                "Welcome back",
                style: TextStyle(fontSize: 38, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              Text(
                "Sign in to continue to your account",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 17),
              ),

              const SizedBox(height: 55),

              LoginTextField(
                controller: emailController,
                label: "Email",
                hint: "Enter email",
                keyboardType: TextInputType.emailAddress,
              ),

              const SizedBox(height: 25),

              LoginTextField(
                controller: passwordController,
                label: "Password",
                hint: "Enter password",
                isPassword: true,
              ),

              const SizedBox(height: 12),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: const Text(
                    "Forgot password?",
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              LoginButton(
                loading: loading,
                onPressed: () async {
                  setState(() {
                    loading = true;
                  });

                  await Future.delayed(const Duration(seconds: 2));

                  setState(() {
                    loading = false;
                  });

                  // TODO:
                  // Firebase Login
                },
              ),
              const SizedBox(height: 30),

              LoginFooter(
                onSignUp: () {
                  // TODO:
                  // Navigate to Sign Up Screen
                },
              ),

              const SizedBox(height: 100),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: TextStyle(color: Colors.grey.shade600),
                  ),

                  GestureDetector(
                    onTap: () {
                      // TODO:
                      // Go to Register
                    },
                    child: const Text(
                      "Sign up",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
