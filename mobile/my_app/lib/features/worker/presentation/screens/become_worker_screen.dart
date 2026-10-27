import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/services/api_service.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../auth/presentation/screens/worker_account_form.dart';

/// Adds the worker role to a client account, then switches into worker mode.
/// Identity verification happens afterwards from the worker home banner.
class BecomeWorkerScreen extends StatefulWidget {
  const BecomeWorkerScreen({super.key, this.api});

  final ApiService? api;

  @override
  State<BecomeWorkerScreen> createState() => _BecomeWorkerScreenState();
}

class _BecomeWorkerScreenState extends State<BecomeWorkerScreen> {
  final _description = TextEditingController();
  String? _category;
  var _saving = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final category = _category;
    if (category == null || _saving) return;
    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Your session has expired.');
      final token = (await user.getIdToken())!;
      final api = widget.api ?? ApiService();
      await api.addRole(
        idToken: token,
        role: 'worker',
        category: category,
        description: _description.text.trim(),
      );
      await api.switchRole(idToken: token, role: 'worker');
      if (!mounted) return;
      // AuthGate is streaming the profile and swaps in the worker home.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.message : error.toString(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : Colors.white;
    final text = dark ? const Color(0xFFF3F3F3) : AppTheme.ink;
    final muted = dark ? const Color(0xFFB8B8B8) : AppTheme.muted;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Become a Worker'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
              children: [
                Text(
                  'Offer your services with this same account. Your client '
                  'requests and history stay as they are, and you can switch '
                  'back from Settings any time.',
                  style: TextStyle(color: muted, height: 1.35),
                ),
                const SizedBox(height: 24),
                Text(
                  'Service category',
                  style: TextStyle(
                    color: text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<String>>(
                  stream: activeServiceCategories(),
                  initialData: fallbackServiceCategories,
                  builder: (context, snapshot) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final category
                          in snapshot.data ?? fallbackServiceCategories)
                        ChoiceChip(
                          key: ValueKey('become-worker-category-$category'),
                          label: Text(category),
                          selected: _category == category,
                          selectedColor: AppTheme.yellow,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _description,
                  maxLines: 3,
                  maxLength: 500,
                  style: TextStyle(color: text),
                  decoration: const InputDecoration(
                    labelText: 'About your work (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Next, verify your identity from the worker home to start '
                  'accepting jobs.',
                  style: TextStyle(color: muted, height: 1.35),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const ValueKey('become-worker-submit'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.yellow,
                    foregroundColor: AppTheme.ink,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _category == null || _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continue as a worker'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
