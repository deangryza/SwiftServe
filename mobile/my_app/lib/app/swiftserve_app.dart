import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';

import '../shared/services/client_theme_controller.dart';
import 'auth_gate.dart';
import '../shared/services/expiry_push_service.dart';

class SwiftServeApp extends StatelessWidget {
  const SwiftServeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: ExpiryPushService.navigatorKey,
      title: 'SwiftServe',
      theme: AppTheme.light,
      builder: (context, child) => ClientThemeScope(child: child!),
      home: const AuthGate(),
    );
  }
}
