import 'package:flutter/material.dart';
import '../services/expiry_push_service.dart';
import '../theme/app_theme.dart';

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
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF3F3F3) : AppTheme.ink;
    final muted = dark ? const Color(0xFFB8B8B8) : AppTheme.muted;
    final border = dark ? const Color(0xFF494949) : AppTheme.line;
    final iconBackground = dark ? const Color(0xFF383838) : AppTheme.softYellow;

    Widget card(String key, Widget child) => Material(
      key: ValueKey('notification-card-$key'),
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    Widget icon(IconData value) => Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: iconBackground, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(
        value,
        color: dark ? AppTheme.yellow : AppTheme.ink,
        size: 21,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in const {
          'enabled': 'Device push notifications',
          'chats': 'Messages',
          'activities': 'Jobs and account updates',
        }.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: card(
              entry.key,
              SwitchListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                secondary: icon(switch (entry.key) {
                  'enabled' => Icons.notifications_outlined,
                  'chats' => Icons.chat_bubble_outline_rounded,
                  _ => Icons.work_outline_rounded,
                }),
                title: Text(
                  entry.value,
                  style: TextStyle(color: text, fontWeight: FontWeight.w700),
                ),
                value: _values?[entry.key] ?? false,
                subtitle: entry.key == 'enabled'
                    ? Text(
                        'For this account on this device. In-app notifications stay available.',
                        style: TextStyle(color: muted, height: 1.25),
                      )
                    : null,
                activeThumbColor: AppTheme.ink,
                activeTrackColor: AppTheme.yellow,
                inactiveThumbColor: muted,
                inactiveTrackColor: border,
                onChanged:
                    _busy || _values == null || !ExpiryPushService.enabled
                    ? null
                    : (value) => _change(entry.key, value),
              ),
            ),
          ),
        card(
          'system',
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            leading: icon(Icons.settings_outlined),
            title: Text(
              'System notification settings',
              style: TextStyle(color: text, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'If permission was denied, allow notifications in your phone settings.',
              style: TextStyle(color: muted, height: 1.25),
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: muted),
            onTap: ExpiryPushService.instance.openSystemSettings,
          ),
        ),
        if (!ExpiryPushService.enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(
              'Device push notifications are unavailable in this version. You can still view updates in Notifications.',
              style: TextStyle(color: muted, height: 1.4),
            ),
          ),
      ],
    );
  }
}
