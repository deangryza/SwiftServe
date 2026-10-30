import 'package:flutter/material.dart';

import 'app/swiftserve_app.dart';
import 'shared/services/expiry_push_service.dart';
import 'shared/services/firebase_bootstrap.dart';
import 'shared/services/client_theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeSwiftServeFirebase();
  await ClientThemeController.initialize();
  await ExpiryPushService.instance.initialize();

  runApp(const SwiftServeApp());
}
