import 'package:flutter/material.dart';

/// Native permission is requested only after an explicit informed Continue tap.
Future<bool> requestPushConsent(
  BuildContext context, {
  required Future<bool> Function() requestPermission,
}) async {
  final consent =
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Stay updated with SwiftServe'),
          content: const Text(
            'Allow alerts for messages, applications, bookings and account updates. Message contents stay private. You can change this in Settings and keep using the app without push notifications.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;
  if (!consent) return false;
  return requestPermission();
}
