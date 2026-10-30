import 'package:my_app/shared/services/expiry_push_service.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';

import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/client_theme_controller.dart';
import '../../../../shared/services/profile_draft_store.dart';
import '../../../../shared/services/profile_photo_picker.dart';
import '../../../../shared/models/worker_service_selection.dart';
import '../widgets/phone_number_field.dart';
import 'client_account_form.dart';
import 'worker_account_form.dart';

class GoogleProfileSetupScreen extends StatefulWidget {
  const GoogleProfileSetupScreen({super.key});

  @override
  State<GoogleProfileSetupScreen> createState() =>
      _GoogleProfileSetupScreenState();
}

class _GoogleProfileSetupScreenState extends State<GoogleProfileSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _category = TextEditingController();
  final _services = WorkerServiceSelection();
  String _role = 'client';
  String _countryCode = '+63';
  bool _saving = false;
  bool _accepted = false;
  Uint8List? _profileImageBytes;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _name.text = user?.displayName?.trim() ?? '';
    _email.text = user?.email?.trim() ?? '';
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
    _services.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    try {
      final bytes = await pickProfilePhoto();
      if (mounted && bytes != null) setState(() => _profileImageBytes = bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not select photo. Try a smaller image.'),
          ),
        );
      }
    }
  }

  Future<void> _chooseRole() async {
    if (_saving) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose your account type',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              _RoleOption(
                icon: Icons.person_outline,
                title: 'I need help',
                subtitle: 'Continue as a Client',
                selected: _role == 'client',
                onTap: () => Navigator.pop(context, 'client'),
              ),
              const SizedBox(height: 10),
              _RoleOption(
                icon: Icons.handyman_outlined,
                title: 'I want to earn',
                subtitle: 'Continue as a Worker',
                selected: _role == 'worker',
                onTap: () => Navigator.pop(context, 'worker'),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && selected != null && selected != _role) {
      setState(() => _role = selected);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_role == 'worker' && _services.validationError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_services.validationError!)));
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    final category = _role == 'worker' ? _category.text.trim() : '';
    final draft = ProfileDraft(
      fullName: _name.text.trim(),
      email: user.email ?? _email.text.trim(),
      phoneNumber: normalizePhoneNumber(_countryCode, _phone.text),
      address: _address.text.trim(),
      role: _role,
      category: category,
      skills: _role == 'worker' ? _services.services : const [],
      photoBase64: _profileImageBytes == null
          ? ''
          : base64Encode(_profileImageBytes!),
    );
    try {
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
        photoBase64: draft.photoBase64,
      );
      await user.updateDisplayName(draft.fullName);
      await ProfileDraftStore().clear();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (error) {
      _showError(
        error.code == 'PHONE_NUMBER_IN_USE'
            ? error.message
            : 'Profile save failed (HTTP ${error.statusCode}). '
                  '${error.statusCode == 401
                      ? 'Sign out and sign in again.'
                      : error.statusCode == 404
                      ? 'Check that the correct SwiftServe backend is running.'
                      : 'Check the backend terminal for the error.'}',
      );
    } on ApiConnectionException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError(
        'Could not save your profile. Check the backend connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _contactAvailability(String kind, String value) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw StateError('Please sign in again.');
    return ApiService().registrationContactAvailable(
      kind,
      value,
      idToken: token,
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signOut() async {
    await ExpiryPushService.instance.beforeSignOut();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    void changeCountry(String value) => setState(() => _countryCode = value);
    final form = _role == 'client'
        ? ClientAccountForm(
            contactAvailability: _contactAvailability,
            key: const ValueKey('google-client-account-flow'),
            formKey: _form,
            name: _name,
            email: _email,
            phone: _phone,
            address: _address,
            password: _password,
            confirmPassword: _confirmPassword,
            acceptedTerms: _accepted,
            onTermsChanged: (value) => setState(() => _accepted = value),
            loading: _saving,
            profileImage: _profileImageBytes,
            onPickImage: _pickProfileImage,
            onRegister: _save,
            countryCode: _countryCode,
            onCountryCodeChanged: changeCountry,
            federatedAccount: true,
            onChangeRole: _chooseRole,
            onExit: _signOut,
          )
        : WorkerAccountForm(
            contactAvailability: _contactAvailability,
            key: const ValueKey('google-worker-account-flow'),
            formKey: _form,
            name: _name,
            email: _email,
            phone: _phone,
            address: _address,
            password: _password,
            confirmPassword: _confirmPassword,
            category: _category,
            services: _services,
            acceptedTerms: _accepted,
            onTermsChanged: (value) => setState(() => _accepted = value),
            loading: _saving,
            profileImage: _profileImageBytes,
            onPickImage: _pickProfileImage,
            onRegister: _save,
            countryCode: _countryCode,
            onCountryCodeChanged: changeCountry,
            federatedAccount: true,
            onChangeRole: _chooseRole,
            onExit: _signOut,
          );
    return ClientThemeScope(child: form);
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? AppTheme.yellow.withValues(alpha: 0.18)
        : Theme.of(context).colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.yellow,
              foregroundColor: AppTheme.ink,
              child: Icon(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(subtitle),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppTheme.yellow),
          ],
        ),
      ),
    ),
  );
}
