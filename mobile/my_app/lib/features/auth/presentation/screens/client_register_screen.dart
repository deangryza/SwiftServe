import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/profile_draft_store.dart';
import 'profile_completion_screen.dart';

class ClientRegisterScreen extends StatelessWidget {
  const ClientRegisterScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const AccountRegistrationScreen(role: 'client');
}

class AccountRegistrationScreen extends StatefulWidget {
  const AccountRegistrationScreen({super.key, required this.role});

  final String role;

  @override
  State<AccountRegistrationScreen> createState() =>
      _AccountRegistrationScreenState();
}

class _AccountRegistrationScreenState extends State<AccountRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _category = TextEditingController();
  bool _acceptedTerms = false;
  bool _loading = false;
  Uint8List? _profileImageBytes;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate() || !_acceptedTerms) {
      if (!_acceptedTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please accept the terms and privacy policy.'),
          ),
        );
      }
      return;
    }
    setState(() => _loading = true);
    final draft = ProfileDraft(
      fullName: _name.text.trim(),
      email: _email.text.trim(),
      phoneNumber: _phone.text.trim(),
      address: _address.text.trim(),
      role: widget.role,
      category: _category.text.trim(),
      skills: _category.text.trim().isEmpty
          ? const []
          : [_category.text.trim()],
    );
    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: draft.email,
            password: _password.text,
          );
      await credential.user?.updateDisplayName(draft.fullName);
      await ProfileDraftStore().save(draft);
      final token = await credential.user!.getIdToken();
      await ApiService().createUserProfile(
        idToken: token!,
        fullName: draft.fullName,
        email: draft.email,
        phoneNumber: draft.phoneNumber,
        address: draft.address,
        role: draft.role,
        category: draft.category,
        skills: draft.skills,
      );
      await ProfileDraftStore().clear();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Could not create the account.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ProfileCompletionScreen()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Account created. Profile setup needs a retry: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _email,
      _phone,
      _address,
      _password,
      _confirmPassword,
      _category,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  Future<void> _pickProfileImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (mounted) setState(() => _profileImageBytes = bytes);
  }

  @override
  Widget build(BuildContext context) => _buildRegistrationScreen(context);

  Widget _buildRegistrationScreen(BuildContext context) {
    final isWorker = widget.role == 'worker';
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F9FF),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 64,
        leadingWidth: 44,
        shape: const Border(bottom: BorderSide(color: Color(0xFFC4C6CD))),
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: SvgPicture.asset('assets/registration/back.svg'),
        ),
        titleSpacing: 0,
        title: const Text(
          'SwiftServe',
          style: TextStyle(
            color: Color(0xFF041627),
            fontSize: 16,
            height: 24 / 16,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 128),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 416),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Create Account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF041627),
                        fontSize: 24,
                        height: 32 / 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.24,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Join our professional service network',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF44474C),
                        fontSize: 14,
                        height: 20 / 14,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCE9FF),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFC4C6CD),
                                width: 2,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0D000000),
                                  offset: Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: _profileImageBytes == null
                                  ? Center(
                                      child: SvgPicture.asset(
                                        'assets/registration/profile.svg',
                                      ),
                                    )
                                  : Image.memory(
                                      _profileImageBytes!,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: SizedBox.square(
                              dimension: 32,
                              child: FilledButton(
                                onPressed: _pickProfileImage,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.all(8),
                                  backgroundColor: const Color(0xFF0058BE),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: SvgPicture.asset(
                                  'assets/registration/camera.svg',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF4FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFC4C6CD)),
                      ),
                      child: Row(
                        children: [
                          SvgPicture.asset('assets/registration/role.svg'),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'CURRENT ROLE',
                                  style: TextStyle(
                                    color: Color(0xFF44474C),
                                    fontSize: 12,
                                    height: 16 / 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                Text(
                                  'Signing up as ${isWorker ? 'Worker' : 'Client'}',
                                  style: const TextStyle(
                                    color: Color(0xFF041627),
                                    fontSize: 14,
                                    height: 20 / 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.maybePop(context),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF0058BE),
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(
                                fontSize: 16,
                                height: 24 / 16,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SvgPicture.asset('assets/registration/shield.svg'),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'To ensure community safety, all users must verify their identity.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 20 / 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _RegistrationField(
                      label: 'Full Name',
                      hintText: 'John Doe',
                      controller: _name,
                      validator: _required,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                    ),
                    const SizedBox(height: 16),
                    _RegistrationField(
                      label: 'Email Address',
                      hintText: 'john@example.com',
                      controller: _email,
                      validator: _required,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 16),
                    _RegistrationField(
                      label: 'Phone Number',
                      hintText: '+1 (555) 000-0000',
                      controller: _phone,
                      validator: _required,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.telephoneNumber],
                    ),
                    const SizedBox(height: 16),
                    _RegistrationField(
                      label: 'Address / Location',
                      hintText: '123 Service Lane, Tech City',
                      controller: _address,
                      validator: _required,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.fullStreetAddress],
                    ),
                    if (isWorker) ...[
                      const SizedBox(height: 16),
                      _RegistrationField(
                        label: 'Primary Service Category',
                        hintText: 'e.g. Plumbing',
                        controller: _category,
                        validator: _required,
                        textInputAction: TextInputAction.next,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _RegistrationField(
                      label: 'Password',
                      hintText: '••••••••',
                      controller: _password,
                      obscureText: true,
                      validator: (value) => (value?.length ?? 0) < 6
                          ? 'Use at least 6 characters.'
                          : null,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    const SizedBox(height: 16),
                    _RegistrationField(
                      label: 'Confirm Password',
                      hintText: '••••••••',
                      controller: _confirmPassword,
                      obscureText: true,
                      validator: (value) => value != _password.text
                          ? 'Passwords do not match.'
                          : null,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _register(),
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          SvgPicture.asset('assets/registration/security.svg'),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Your data is encrypted and stored securely.',
                              style: TextStyle(
                                color: Color(0xFF44474C),
                                fontSize: 14,
                                height: 20 / 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _acceptedTerms,
                            onChanged: (value) =>
                                setState(() => _acceptedTerms = value ?? false),
                            side: const BorderSide(color: Color(0xFFC4C6CD)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: TextStyle(
                                color: Color(0xFF44474C),
                                fontSize: 14,
                                height: 20 / 14,
                              ),
                              children: [
                                TextSpan(text: 'I agree to the '),
                                TextSpan(
                                  text: 'Terms and Conditions',
                                  style: TextStyle(color: Color(0xFF0058BE)),
                                ),
                                TextSpan(text: ' and '),
                                TextSpan(
                                  text: 'Privacy Policy.',
                                  style: TextStyle(color: Color(0xFF0058BE)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 60,
                      child: FilledButton(
                        onPressed: _loading ? null : _register,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF18181B),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xA618181B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 20,
                            height: 28 / 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        child: _loading
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Create Account'),
                                    const SizedBox(width: 8),
                                    SvgPicture.asset(
                                      'assets/registration/arrow.svg',
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextButton(
                      onPressed: () => Navigator.maybePop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF0058BE),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 20),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      child: const Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Already have an account? ',
                              style: TextStyle(color: Color(0xFF44474C)),
                            ),
                            TextSpan(text: 'Log In'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegistrationField extends StatelessWidget {
  const _RegistrationField({
    required this.label,
    required this.hintText,
    required this.controller,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofillHints,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF0B1C30),
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          obscureText: obscureText,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          autofillHints: autofillHints,
          style: const TextStyle(color: Color(0xFF041627), fontSize: 16),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(
              color: Color(0xFFC4C6CD),
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: const EdgeInsets.fromLTRB(16, 15, 17, 15),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFC4C6CD)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF0058BE),
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFFBA1A1A),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
