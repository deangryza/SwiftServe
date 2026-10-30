import 'package:my_app/shared/services/expiry_push_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../features/worker/presentation/screens/become_worker_screen.dart';
import '../models/app_user.dart';
import '../services/api_service.dart';
import '../services/client_theme_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/action_confirmation_dialog.dart';
import '../widgets/push_notification_preferences.dart';

/// Shared settings presentation for the client and worker experiences.
class SwiftServeSettingsScreen extends StatelessWidget {
  const SwiftServeSettingsScreen({
    super.key,
    required this.darkModeTitle,
    required this.darkModeSubtitle,
    required this.darkModeToggleKey,
    this.profile,
  });

  final String darkModeTitle;
  final String darkModeSubtitle;
  final Key darkModeToggleKey;

  /// Enables the client/worker switch; admins never see it.
  final AppUser? profile;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF171717) : Colors.white;
    final surface = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final text = dark ? const Color(0xFFF3F3F3) : AppTheme.ink;
    final muted = dark ? const Color(0xFFB8B8B8) : AppTheme.muted;
    final border = dark ? const Color(0xFF494949) : AppTheme.line;
    final iconBackground = dark ? const Color(0xFF383838) : AppTheme.softYellow;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          key: const ValueKey('settings-back'),
          onPressed: () => Navigator.pop(context),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Settings'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
              children: [
                _SectionLabel(label: 'Appearance', color: muted),
                const SizedBox(height: 10),
                Material(
                  color: surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: ClientThemeController.darkMode,
                    builder: (context, darkMode, _) => SwitchListTile(
                      key: darkModeToggleKey,
                      contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                      secondary: _SettingsIcon(
                        icon: darkMode
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        background: iconBackground,
                        foreground: darkMode ? AppTheme.yellow : AppTheme.ink,
                      ),
                      title: Text(
                        darkModeTitle,
                        style: TextStyle(
                          color: text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          darkModeSubtitle,
                          style: TextStyle(color: muted, height: 1.25),
                        ),
                      ),
                      value: darkMode,
                      activeThumbColor: AppTheme.ink,
                      activeTrackColor: AppTheme.yellow,
                      inactiveThumbColor: muted,
                      inactiveTrackColor: border,
                      onChanged: ClientThemeController.setDarkMode,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _SectionLabel(label: 'Notifications', color: muted),
                const PushNotificationPreferences(),
                const SizedBox(height: 28),
                _SectionLabel(label: 'Account', color: muted),
                const SizedBox(height: 10),
                Material(
                  color: surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      if (profile != null &&
                          profile!.role != UserRole.admin) ...[
                        _RoleSwitchTile(
                          profile: profile!,
                          text: text,
                          muted: muted,
                          iconBackground: iconBackground,
                        ),
                        Divider(height: 1, color: border),
                      ],
                      ListTile(
                        key: const ValueKey('settings-log-out'),
                        contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                        leading: _SettingsIcon(
                          icon: Icons.logout_rounded,
                          background: iconBackground,
                          foreground: text,
                        ),
                        title: Text(
                          'Log out',
                          style: TextStyle(
                            color: text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: muted,
                        ),
                        onTap: () => _logOut(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _logOut(BuildContext context) async {
    final confirmed = await showActionConfirmation(
      context,
      title: 'Log out?',
      message: 'Are you sure you want to log out of your SwiftServe account?',
      confirmLabel: 'Log out',
      icon: Icons.logout_rounded,
    );
    if (!confirmed) return;
    await ExpiryPushService.instance.beforeSignOut();
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class _RoleSwitchTile extends StatefulWidget {
  const _RoleSwitchTile({
    required this.profile,
    required this.text,
    required this.muted,
    required this.iconBackground,
  });

  final AppUser profile;
  final Color text;
  final Color muted;
  final Color iconBackground;

  @override
  State<_RoleSwitchTile> createState() => _RoleSwitchTileState();
}

class _RoleSwitchTileState extends State<_RoleSwitchTile> {
  var _busy = false;

  UserRole get _target => widget.profile.otherRole;
  bool get _owned => widget.profile.hasRole(_target);
  bool get _toWorker => _target == UserRole.worker;

  String get _title => _owned
      ? (_toWorker ? 'Switch to Worker' : 'Switch to Client')
      : (_toWorker ? 'Become a Worker' : 'Also hire as a Client');

  String get _subtitle => _toWorker
      ? 'Find jobs and earn with the same account'
      : 'Post requests and hire workers with the same account';

  Future<void> _onTap() async {
    if (!_owned && _toWorker) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BecomeWorkerScreen()),
      );
      return;
    }
    final label = _toWorker ? 'worker' : 'client';
    final confirmed = await showActionConfirmation(
      context,
      title: _owned ? 'Switch to $label mode?' : 'Add a client account?',
      message: _owned
          ? 'You can switch back any time from Settings.'
          : 'Your worker profile stays as it is. You can switch back any time from Settings.',
      confirmLabel: _owned ? 'Switch' : 'Add and switch',
      icon: Icons.swap_horiz_rounded,
      confirmButtonKey: const ValueKey('settings-role-confirm'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Your session has expired.');
      final token = (await user.getIdToken())!;
      final api = ApiService();
      if (!_owned) await api.addRole(idToken: token, role: label);
      await api.switchRole(idToken: token, role: label);
      if (!mounted) return;
      // AuthGate is streaming the profile and swaps in the other home.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
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
  Widget build(BuildContext context) => ListTile(
    key: const ValueKey('settings-switch-role'),
    contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
    leading: _SettingsIcon(
      icon: _toWorker ? Icons.handyman_rounded : Icons.person_search_rounded,
      background: widget.iconBackground,
      foreground: widget.text,
    ),
    title: Text(
      _title,
      style: TextStyle(color: widget.text, fontWeight: FontWeight.w700),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        _subtitle,
        style: TextStyle(color: widget.muted, height: 1.25),
      ),
    ),
    trailing: _busy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(Icons.chevron_right_rounded, color: widget.muted),
    onTap: _busy ? null : _onTap,
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: TextStyle(
      color: color,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
  );
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(color: background, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: Icon(icon, color: foreground, size: 21),
  );
}
