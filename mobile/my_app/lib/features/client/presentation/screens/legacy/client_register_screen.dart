import 'package:flutter/material.dart';
import '../../widgets/legacy/profile_picker.dart';
import '../../widgets/legacy/registration_text_field.dart';
import '../../widgets/legacy/registration_primary_button.dart';
import '../../widgets/legacy/role_card.dart';
import '../../widgets/legacy/terms_checkbox.dart';
import '../../widgets/legacy/info_card.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final fullName = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();

  bool agree = false;
  bool loading = false;

  String selectedRole = "Job Seeker";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          "Create Account",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const ProfilePicker(),
              const SizedBox(height: 20),

              const InfoCard(
                title: "Identity Verification",
                subtitle:
                    "Please upload a clear profile picture. This helps employers verify your account and improves your chances of getting hired.",
                icon: Icons.verified_user_outlined,
              ),

              const SizedBox(height: 25),

              const SizedBox(height: 25),

              RegistrationTextField(
                controller: fullName,
                label: "Full Name",
                hint: "Enter your full name",
                icon: Icons.person_outline,
              ),

              RegistrationTextField(
                controller: email,
                label: "Email",
                hint: "Enter your email",
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),

              RegistrationTextField(
                controller: phone,
                label: "Phone Number",
                hint: "09XXXXXXXXX",
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),

              RegistrationTextField(
                controller: password,
                label: "Password",
                hint: "******",
                icon: Icons.lock_outline,
                isPassword: true,
              ),

              RegistrationTextField(
                controller: confirmPassword,
                label: "Confirm Password",
                hint: "******",
                icon: Icons.lock_outline,
                isPassword: true,
              ),

              const SizedBox(height: 20),

              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Select Role",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: RoleCard(
                      title: "Job Seeker",
                      icon: Icons.person,
                      selected: selectedRole == "Job Seeker",
                      onTap: () {
                        setState(() {
                          selectedRole = "Job Seeker";
                        });
                      },
                    ),
                  ),

                  const SizedBox(width: 15),

                  Expanded(
                    child: RoleCard(
                      title: "Employer",
                      icon: Icons.business_center,
                      selected: selectedRole == "Employer",
                      onTap: () {
                        setState(() {
                          selectedRole = "Employer";
                        });
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              TermsCheckbox(
                value: agree,
                onChanged: (value) {
                  setState(() {
                    agree = value!;
                  });
                },
                onTermsTap: () {
                  showDialog(
                    context: context,

                    builder: (_) {
                      return AlertDialog(
                        title: const Text("Terms & Conditions"),

                        content: const SingleChildScrollView(
                          child: Text(
                            "By creating an account, you agree to follow the rules and policies of SwiftServe. "
                            "Your information will only be used for account verification and job matching.",
                          ),
                        ),

                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },

                            child: const Text("Close"),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 25),

              RegistrationPrimaryButton(
                text: "Create Account",
                loading: loading,
                onPressed: () async {
                  // Check kung tinanggap ang Terms & Conditions
                  if (!agree) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Please accept the Terms & Conditions."),
                      ),
                    );
                    return;
                  }

                  // Loading
                  setState(() {
                    loading = true;
                  });

                  await Future.delayed(const Duration(seconds: 2));

                  setState(() {
                    loading = false;
                  });
                },
              ),

              const SizedBox(height: 25),
            ],
          ),
        ),
      ),
    );
  }

  Widget roleCard(String role) {
    bool selected = selectedRole == role;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedRole = role;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade50 : Colors.white,

          borderRadius: BorderRadius.circular(15),

          border: Border.all(
            color: selected ? Colors.blue : Colors.grey.shade300,
          ),
        ),
        child: Column(
          children: [
            Icon(
              role == "Employer" ? Icons.business : Icons.person,

              color: selected ? Colors.blue : Colors.grey,
            ),

            const SizedBox(height: 8),

            Text(
              role,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: selected ? Colors.blue : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
