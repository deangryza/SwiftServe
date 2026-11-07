import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../shared/legal/terms_and_conditions.dart';
import '../../../../shared/legal/security_policy.dart';
import '../../../../shared/theme/app_theme.dart';

/// Both controls edit the same consent value; reading a policy never accepts it.
class PolicyDialog extends StatefulWidget {
  const PolicyDialog({
    super.key,
    required this.terms,
    required this.consent,
    required this.onChanged,
  });

  final bool terms;
  final ValueListenable<(bool, bool)> consent;
  final ValueChanged<bool> onChanged;

  @override
  State<PolicyDialog> createState() => _PolicyDialogState();
}

class _PolicyDialogState extends State<PolicyDialog> {
  final _scroll = ScrollController();
  bool _expanded = false;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      key: const ValueKey('policy-dialog'),
      insetPadding: _expanded
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_expanded ? 0 : 24),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        key: const ValueKey('policy-sheet'),
        width: _expanded ? double.infinity : 640,
        height: _expanded
            ? double.infinity
            : MediaQuery.sizeOf(context).height * .8,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.terms
                            ? 'Terms and Conditions'
                            : 'Security Policy',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('policy-expand'),
                      tooltip: _expanded
                          ? 'Restore popup size'
                          : 'Expand policy',
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Icon(
                        _expanded
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('policy-close'),
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    key: const ValueKey('policy-scroll'),
                    controller: _scroll,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelectionArea(
                          child: _PolicyText(
                            text: widget.terms
                                ? swiftServeTermsAndConditions
                                : swiftServeSecurityPolicy,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        ValueListenableBuilder<(bool, bool)>(
                          valueListenable: widget.consent,
                          builder: (context, state, _) => CheckboxListTile(
                            key: ValueKey(
                              widget.terms
                                  ? 'terms-dialog-consent'
                                  : 'security-dialog-consent',
                            ),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: state.$1,
                            onChanged: state.$2
                                ? (value) => widget.onChanged(value ?? false)
                                : null,
                            activeColor: AppTheme.yellow,
                            checkColor: AppTheme.ink,
                            title: const Text(
                              'I have read and agree to the Terms and Conditions and Security Policy.',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.ink,
                              backgroundColor: AppTheme.yellow,
                            ),
                            child: const Text('Close'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders only the headings, bold spans and paragraphs used in the supplied
/// document. No HTML, external links, scripts or new rendering dependency.
class _PolicyText extends StatelessWidget {
  const _PolicyText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final paragraph in text.split(RegExp(r'\n\s*\n')))
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text.rich(
            _inline(paragraph.replaceFirst(RegExp(r'^#{1,3}\s+'), '')),
            style: paragraph.startsWith('#')
                ? Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  )
                : Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ),
    ],
  );

  TextSpan _inline(String paragraph) {
    final spans = <TextSpan>[];
    var offset = 0;
    for (final match in RegExp(r'\*\*(.+?)\*\*').allMatches(paragraph)) {
      spans.add(TextSpan(text: paragraph.substring(offset, match.start)));
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
      offset = match.end;
    }
    spans.add(TextSpan(text: paragraph.substring(offset)));
    return TextSpan(children: spans);
  }
}
