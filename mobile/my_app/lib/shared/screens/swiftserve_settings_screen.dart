import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/client_theme_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/action_confirmation_dialog.dart';

/// Shared settings presentation for the client and worker experiences.
class SwiftServeSettingsScreen extends StatelessWidget {
  const SwiftServeSettingsScreen({
    super.key,
    required this.darkModeTitle,
    required this.darkModeSubtitle,
    required this.darkModeToggleKey,
  });

  final String darkModeTitle;
  final String darkModeSubtitle;
  final Key darkModeToggleKey;

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
                _SectionLabel(label: 'Account', color: muted),
                const SizedBox(height: 10),
                Material(
                  color: surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
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
                    trailing: Icon(Icons.chevron_right_rounded, color: muted),
                    onTap: () => _logOut(context),
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
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
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
