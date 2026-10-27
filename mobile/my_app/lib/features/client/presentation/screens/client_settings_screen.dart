import 'package:flutter/material.dart';

import '../../../../shared/models/app_user.dart';
import '../../../../shared/screens/swiftserve_settings_screen.dart';

class ClientSettingsScreen extends StatelessWidget {
  const ClientSettingsScreen({super.key, this.profile});

  final AppUser? profile;

  @override
  Widget build(BuildContext context) => SwiftServeSettingsScreen(
    darkModeTitle: 'Dark theme',
    darkModeSubtitle: 'Apply dark mode to the client app only',
    darkModeToggleKey: const ValueKey('client-dark-mode-toggle'),
    profile: profile,
  );
}
