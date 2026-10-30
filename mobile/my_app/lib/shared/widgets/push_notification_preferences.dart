import 'package:flutter/material.dart';
import '../services/expiry_push_service.dart';

class PushNotificationPreferences extends StatefulWidget {
  const PushNotificationPreferences({super.key});
  @override
  State<PushNotificationPreferences> createState() =>
      _PushNotificationPreferencesState();
}

class _PushNotificationPreferencesState
    extends State<PushNotificationPreferences> {
  Map<String, bool>? _values;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await ExpiryPushService.instance.preferences();
    if (mounted) setState(() => _values = values);
  }

  Future<void> _change(String key, bool value) async {
    setState(() => _busy = true);
    try {
      await ExpiryPushService.instance.updatePreferences(context, {
        ..._values!,
        key: value,
      });
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Could not update device notifications. Try again when connected.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final entry in const {
        'enabled': 'Device push notifications',
        'chats': 'Messages',
        'activities': 'Jobs and account updates',
      }.entries)
        SwitchListTile(
          title: Text(entry.value),
          value: _values?[entry.key] ?? false,
          subtitle: entry.key == 'enabled'
              ? const Text(
                  'For this account on this device. In-app notifications stay available.',
                )
              : null,
          onChanged: _busy || _values == null || !ExpiryPushService.enabled
              ? null
              : (value) => _change(entry.key, value),
        ),
      ListTile(
        title: const Text('System notification settings'),
        subtitle: const Text(
          'If permission was denied, allow notifications in your phone settings.',
        ),
        onTap: ExpiryPushService.instance.openSystemSettings,
      ),
      if (!ExpiryPushService.enabled)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Push delivery is not enabled in this build.'),
        ),
    ],
  );
}
