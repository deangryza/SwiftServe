import 'policy_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../shared/theme/app_theme.dart';

/// Shared controlled consent state for the inline checkbox and policy popup.
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

  final _consent = ValueNotifier<(bool, bool)>((false, true));

  @override
  void initState() {
    super.initState();
    _consent.value = (widget.value, widget.enabled);
  }

  @override
  void didUpdateWidget(covariant PolicyConsent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_consent.value != (widget.value, widget.enabled)) {
      // The popup is a separate route, not a descendant of this build. Notify
      // it after the frame rather than rebuilding another route during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _consent.value = (widget.value, widget.enabled);
      });
    }
  }

  void _change(bool value) {
    if (!mounted || !widget.enabled) return;
    _consent.value = (value, widget.enabled);
    widget.onChanged(value);
  }

  void _open(bool terms) {
    showDialog<void>(
      context: context,
      builder: (context) =>
          PolicyDialog(terms: terms, consent: _consent, onChanged: _change),
    );
  }

  @override
  void dispose() {
    _consent.dispose();
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
                  ? (value) => _change(value ?? false)
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
