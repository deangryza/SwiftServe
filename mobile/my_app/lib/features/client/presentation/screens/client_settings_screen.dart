import 'package:flutter/material.dart';

import '../../../../shared/screens/swiftserve_settings_screen.dart';

class ClientSettingsScreen extends StatelessWidget {
  const ClientSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const SwiftServeSettingsScreen(
    darkModeTitle: 'Dark theme',
    darkModeSubtitle: 'Apply dark mode to the client app only',
    darkModeToggleKey: ValueKey('client-dark-mode-toggle'),
  );
}
