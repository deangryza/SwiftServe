import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/profile_draft_store.dart';
import 'profile_completion_screen.dart';

class ClientRegisterScreen extends StatelessWidget {
  const ClientRegisterScreen({super.key});

  @override
  Widget build(BuildContext context) => const AccountRegistrationScreen(
    role: 'client',
    title: 'Create a client account',
  );
}

class AccountRegistrationScreen extends StatefulWidget {
  const AccountRegistrationScreen({
    super.key,
    required this.role,
    required this.title,
  });

  final String role;
  final String title;

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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Center(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: _required,
            ),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              validator: _required,
            ),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
              keyboardType: TextInputType.phone,
              validator: _required,
            ),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address'),
              validator: _required,
            ),
            if (widget.role == 'worker')
              TextFormField(
                controller: _category,
                decoration: const InputDecoration(
                  labelText: 'Primary service category',
                ),
                validator: _required,
              ),
            TextFormField(
              controller: _password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              validator: (value) => (value?.length ?? 0) < 6
                  ? 'Use at least 6 characters.'
                  : null,
            ),
            TextFormField(
              controller: _confirmPassword,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              obscureText: true,
              validator: (value) =>
                  value != _password.text ? 'Passwords do not match.' : null,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _acceptedTerms,
              onChanged: (value) =>
                  setState(() => _acceptedTerms = value ?? false),
              title: const Text('I accept the Terms and Privacy Policy.'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _register,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Create account'),
            ),
          ],
        ),
      ),
    ),
  );
}
