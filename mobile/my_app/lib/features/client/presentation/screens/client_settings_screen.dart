import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/services/client_theme_controller.dart';

class ClientSettingsScreen extends StatelessWidget {
  const ClientSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ValueListenableBuilder<bool>(
            valueListenable: ClientThemeController.darkMode,
            builder: (context, darkMode, _) => SwitchListTile(
              secondary: Icon(darkMode ? Icons.dark_mode : Icons.light_mode),
              title: const Text('Dark theme'),
              subtitle: const Text('Apply dark mode to the client app only'),
              value: darkMode,
              activeThumbColor: const Color(0xFFFFC72C),
              onChanged: ClientThemeController.setDarkMode,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log out'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ),
      ],
    ),
  );
}
