import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:http/http.dart' as http;

class ClientRegisterScreen extends StatefulWidget {
  const ClientRegisterScreen({super.key});

  @override
  State<ClientRegisterScreen> createState() =>
      _ClientRegisterScreenState();
}

class _ClientRegisterScreenState
    extends State<ClientRegisterScreen> {
  final fullNameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();

  String completePhoneNumber = '';

  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool validateForm() {
  if (fullNameController.text.trim().isEmpty) {
    showMessage('Please enter your full name.');
    return false;
  }

  if (emailController.text.trim().isEmpty) {
    showMessage('Please enter your email address.');
    return false;
  }

  if (completePhoneNumber.isEmpty) {
    showMessage('Please enter your phone number.');
    return false;
  }

  if (addressController.text.trim().isEmpty) {
    showMessage('Please enter your address.');
    return false;
  }

  if (passwordController.text.isEmpty) {
    showMessage('Please enter a password.');
    return false;
  }

  if (passwordController.text.length < 6) {
    showMessage('Password must be at least 6 characters.');
    return false;
  }

  if (passwordController.text != confirmPasswordController.text) {
    showMessage('Passwords do not match.');
    return false;
  }

  if (!acceptedTerms) {
    showMessage('Please accept the Terms and Conditions.');
    return false;
  }

  return true;
}

void showMessage(String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
    ),
  );
}

  bool acceptedTerms = false;
  bool isPasswordVisible = false;
  bool isConfirmPasswordVisible = false;


  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    addressController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();

    super.dispose();
  }

  Future<void> createAccount() async {
  if (!validateForm()) {
    return;
  }

  try {
    // 1. Create Firebase Authentication account
    final credential =
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: emailController.text.trim(),
      password: passwordController.text,
    );

    final user = credential.user;

    if (user == null) {
      showMessage('Account creation failed.');
      return;
    }

    // 2. Get Firebase ID token
    final idToken = await user.getIdToken();

    if (idToken == null) {
      showMessage('Could not get authentication token.');
      return;
    }

    // 3. Send profile information to Node.js backend
    final response = await http.post(
      Uri.parse('http://localhost:5000/api/users/profile'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'fullName': fullNameController.text.trim(),
        'email': emailController.text.trim(),
        'phoneNumber': completePhoneNumber,
        'address': addressController.text.trim(),
        'role': 'client',
      }),
    );

    // 4. Check backend response
    if (response.statusCode == 200 ||
        response.statusCode == 201) {
      print('Profile saved successfully.');
      print(response.body);

      if (!mounted) return;

      showMessage('Account created successfully!');

      // Next step: navigate to Client Home
    } else {
      print('Profile save failed.');
      print('Status code: ${response.statusCode}');
      print('Response: ${response.body}');

      if (!mounted) return;

      showMessage(
        'Account created, but profile could not be saved.',
      );
    }
  } on FirebaseAuthException catch (e) {
    String message = 'Something went wrong.';

    if (e.code == 'email-already-in-use') {
      message = 'This email is already registered.';
    } else if (e.code == 'invalid-email') {
      message = 'Please enter a valid email address.';
    } else if (e.code == 'weak-password') {
      message = 'Password is too weak.';
    }

    showMessage(message);
  } catch (e) {
    print('Registration error: $e');
    showMessage('An unexpected error occurred.');
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 700;

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isDesktop ? 430 : 500,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            icon: const Icon(
                              Icons.arrow_back_ios_new,
                              size: 18,
                            ),
                          ),

                          const SizedBox(width: 4),

                          const Text(
                            'SwiftServe',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Title
                      const Text(
                        'Create Account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10233B),
                        ),
                      ),

                      const SizedBox(height: 5),

                      const Text(
                        'Join our professional service network',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Profile photo
                      Center(
                        child: Stack(
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFE7EDF5),
                                border: Border.all(
                                  color: const Color(0xFFD0D7E2),
                                ),
                              ),
                              child: const Icon(
                                Icons.person_outline,
                                size: 38,
                                color: Colors.black45,
                              ),
                            ),

                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 23,
                                height: 23,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF1677D2),
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  size: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Current role
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFD4E4F8),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.badge_outlined,
                              color: Color(0xFF1677D2),
                              size: 20,
                            ),

                            const SizedBox(width: 10),

                            const Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'CURRENT ROLE',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Signing up as Client',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              child: const Text(
                                'Change',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF1677D2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Security notice
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE1F7EC),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: Color(0xFF00A86B),
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'To ensure community safety, all users must verify their identity.',
                                style: TextStyle(
                                  fontSize: 10,
                                  height: 1.4,
                                  color: Color(0xFF087A52),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Full Name
                      _buildLabel('Full Name'),

                      _buildTextField(
                        controller: fullNameController,
                        hint: 'John Doe',
                        icon: Icons.person_outline,
                      ),

                      const SizedBox(height: 12),

                      // Email
                      _buildLabel('Email Address'),

                      _buildTextField(
                        controller: emailController,
                        hint: 'john@example.com',
                        icon: Icons.email_outlined,
                        keyboardType:
                            TextInputType.emailAddress,
                      ),

                      const SizedBox(height: 12),

                      // Phone
                      _buildLabel('Phone Number'),
                      IntlPhoneField(
                        controller: phoneController,
                        initialCountryCode: 'PH',
                        decoration: InputDecoration(
                          hintText: '917 123 4567',
                          hintStyle: const TextStyle(
                            fontSize: 11,
                            color: Colors.black26,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(
                              color: Color(0xFFDDE2E8),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(
                              color: Color(0xFFDDE2E8),
                            ),
                          ),
                        ),
                        onChanged: (phone) {
                          completePhoneNumber = phone.completeNumber;
                        },
                      ),

                      const SizedBox(height: 12),

                      // Address
                      _buildLabel('Address / Location'),

                      _buildTextField(
                        controller: addressController,
                        hint: '123 Service Lane, Tech City',
                        icon: Icons.location_on_outlined,
                      ),

                      const SizedBox(height: 12),

                      // Password
                      _buildLabel('Password'),

                      _buildPasswordField(
                        controller: passwordController,
                        hint: '••••••••',
                        visible: isPasswordVisible,
                        onToggle: () {
                          setState(() {
                            isPasswordVisible =
                                !isPasswordVisible;
                          });
                        },
                      ),

                      const SizedBox(height: 12),

                      // Confirm Password
                      _buildLabel('Confirm Password'),

                      _buildPasswordField(
                        controller: confirmPasswordController,
                        hint: '••••••••',
                        visible: isConfirmPasswordVisible,
                        onToggle: () {
                          setState(() {
                            isConfirmPasswordVisible =
                                !isConfirmPasswordVisible;
                          });
                        },
                      ),

                      const SizedBox(height: 10),

                      const Text(
                        'Your data is encrypted and stored securely.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.black45,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Terms
                      CheckboxListTile(
                        value: acceptedTerms,
                        onChanged: (value) {
                          setState(() {
                            acceptedTerms = value ?? false;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        controlAffinity:
                            ListTileControlAffinity.leading,
                        title: const Text.rich(
                          TextSpan(
                            text:
                                'I agree to the Terms and Conditions and ',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.black54,
                            ),
                            children: [
                              TextSpan(
                                text: 'Privacy Policy.',
                                style: TextStyle(
                                  color: Color(0xFF1677D2),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Create Account
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: createAccount,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(8),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Text(
                                'Create Account',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward,
                                size: 17,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextButton(
                        onPressed: () {
                          // Login screen will be connected later.
                        },
                        child: const Text.rich(
                          TextSpan(
                            text: 'Already have an account? ',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.black54,
                            ),
                            children: [
                              TextSpan(
                                text: 'Log In',
                                style: TextStyle(
                                  color: Color(0xFF1677D2),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xFF26364A),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 11,
          color: Colors.black26,
        ),
        prefixIcon: Icon(
          icon,
          size: 17,
          color: Colors.black38,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(
            color: Color(0xFFDDE2E8),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(
            color: Color(0xFFDDE2E8),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool visible,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 11,
          color: Colors.black26,
        ),
        prefixIcon: const Icon(
          Icons.lock_outline,
          size: 17,
          color: Colors.black38,
        ),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            visible
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 17,
          ),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(
            color: Color(0xFFDDE2E8),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(
            color: Color(0xFFDDE2E8),
          ),
        ),
      ),
    );
  }
}