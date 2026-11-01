import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../shared/theme/app_theme.dart';

/// Shared consent UI. Policy summaries require product-owner review for release.
class PolicyConsent extends StatefulWidget {
  const PolicyConsent({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.showError = false,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final bool showError;

  static const requiredMessage =
      'Please accept the Terms and Conditions and Security Policy to continue.';

  @override
  State<PolicyConsent> createState() => _PolicyConsentState();
}

class _PolicyConsentState extends State<PolicyConsent> {
  late final _terms = TapGestureRecognizer()..onTap = () => _open(true);
  late final _security = TapGestureRecognizer()..onTap = () => _open(false);

  void _open(bool terms) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(terms ? 'Terms and Conditions' : 'Security Policy'),
        content: SingleChildScrollView(
          child: Text(
            terms
                ? 'SwiftServe connects clients and workers for service requests. '
                      'Provide accurate account and job information, communicate '
                      'respectfully, and only accept work you can perform. Do not '
                      'impersonate others, misuse their information, or use the app '
                      'for unlawful activity. Review the service details and '
                      'schedule before applying for or accepting a job.'
                : 'Keep your password and sign-in codes private. Do not share '
                      'identity documents or sensitive personal information in '
                      'public profiles or chat messages. Your public profile, '
                      'including your About information and services, can be seen '
                      'by other users. Review the information you publish. '
                      'Manage photo, location, and notification permissions in '
                      'your device settings.',
            style: const TextStyle(height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.ink,
              backgroundColor: AppTheme.yellow,
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _terms.dispose();
    _security.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const linkStyle = TextStyle(
      color: AppTheme.ink,
      backgroundColor: AppTheme.softYellow,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: AppTheme.ink,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: const ValueKey('policy-consent-checkbox'),
              value: widget.value,
              onChanged: widget.enabled
                  ? (value) => widget.onChanged(value ?? false)
                  : null,
              activeColor: AppTheme.yellow,
              checkColor: AppTheme.ink,
              semanticLabel: 'Accept Terms and Conditions and Security Policy',
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'I have read and agree to the '),
                      TextSpan(
                        text: 'Terms and Conditions',
                        style: linkStyle,
                        recognizer: _terms,
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Security Policy',
                        style: linkStyle,
                        recognizer: _security,
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (widget.showError && !widget.value)
          const Padding(
            padding: EdgeInsets.only(left: 12, bottom: 8),
            child: Text(
              PolicyConsent.requiredMessage,
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
