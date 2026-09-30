import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/profile_draft_store.dart';

class ProfileCompletionScreen extends StatefulWidget {
  const ProfileCompletionScreen({super.key});

  @override
  State<ProfileCompletionScreen> createState() =>
      _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState extends State<ProfileCompletionScreen> {
  ProfileDraft? _draft;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final draft = await ProfileDraftStore().load();
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _loading = false;
    });
  }

  Future<void> _retry() async {
    final user = FirebaseAuth.instance.currentUser;
    final draft = _draft;
    if (user == null || draft == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await user.getIdToken(true);
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
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Complete profile')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 52),
                  const SizedBox(height: 16),
                  Text(
                    _draft == null
                        ? 'No saved profile draft was found. Sign out and register again.'
                        : 'Your account exists, but the SwiftServe profile has not been saved yet.',
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_draft != null)
                    FilledButton(
                      onPressed: _retry,
                      child: const Text('Retry profile setup'),
                    ),
                  TextButton(
                    onPressed: _signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
      ),
    ),
  );
}
