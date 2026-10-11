import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/profile_draft_store.dart';

class GoogleProfileSetupScreen extends StatefulWidget {
  const GoogleProfileSetupScreen({super.key});

  @override
  State<GoogleProfileSetupScreen> createState() =>
      _GoogleProfileSetupScreenState();
}

class _GoogleProfileSetupScreenState extends State<GoogleProfileSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(
    text: FirebaseAuth.instance.currentUser?.displayName ?? '',
  );
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _category = TextEditingController();
  String _role = 'client';
  bool _saving = false;
  bool _accepted = false;

  @override
  void dispose() {
    for (final controller in [_name, _phone, _address, _category]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (!_accepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the terms and privacy policy.'),
        ),
      );
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final category = _role == 'worker' ? _category.text.trim() : '';
      final draft = ProfileDraft(
        fullName: _name.text.trim(),
        email: user.email ?? '',
        phoneNumber: _phone.text.trim(),
        address: _address.text.trim(),
        role: _role,
        category: category,
        skills: category.isEmpty ? [] : [category],
      );
      await ProfileDraftStore().save(draft);
      final token = await user.getIdToken();
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
      await user.updateDisplayName(draft.fullName);
      await ProfileDraftStore().clear();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (error) {
      _showError(
        'Profile save failed (HTTP ${error.statusCode}). '
        '${error.statusCode == 401
            ? 'Sign out and sign in again.'
            : error.statusCode == 404
            ? 'Check that the correct SwiftServe backend is running.'
            : 'Check the backend terminal for the error.'}',
      );
    } on ApiConnectionException catch (error) {
      _showError(error.message);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save your profile. Check the backend connection and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_saving,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (value) => value == null || value.trim().isEmpty
          ? 'This field is required.'
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Complete your account')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    FirebaseAuth.instance.currentUser?.email ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Choose how you will use SwiftServe and complete your profile.',
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    decoration: const InputDecoration(
                      labelText: 'Account type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'client',
                        child: Text('I need help — Client'),
                      ),
                      DropdownMenuItem(
                        value: 'worker',
                        child: Text('I want to earn — Worker'),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _role = value!),
                  ),
                  const SizedBox(height: 20),
                  _field('Full name', _name),
                  _field('Phone number', _phone, keyboard: TextInputType.phone),
                  _field('Address', _address),
                  if (_role == 'worker') _field('Service category', _category),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _accepted,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _accepted = value ?? false),
                    title: const Text(
                      'I agree to the Terms and Conditions and Privacy Policy.',
                    ),
                  ),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving...' : 'Continue'),
                  ),
                  TextButton(
                    onPressed: _saving ? null : FirebaseAuth.instance.signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
