import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shows the app-wide confirmation dialog used for destructive or consequential
/// actions. Routine navigation should not use this dialog.
Future<bool> showActionConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  IconData icon = Icons.warning_amber_rounded,
  Key? confirmButtonKey,
}) async {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
  final text = dark ? const Color(0xFFF3F3F3) : AppTheme.ink;
  final muted = dark ? const Color(0xFFB8B8B8) : AppTheme.muted;

  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Theme.of(dialogContext).dividerColor),
          ),
          icon: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppTheme.softYellow,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(icon, color: AppTheme.ink, size: 28),
            ),
          ),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: text, fontWeight: FontWeight.w800),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, height: 1.4),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            SizedBox(
              width: 120,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: text,
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(color: Theme.of(dialogContext).dividerColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(cancelLabel),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: FilledButton(
                key: confirmButtonKey,
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.yellow,
                  foregroundColor: AppTheme.ink,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(confirmLabel),
              ),
            ),
          ],
        ),
      ) ??
      false;
}
