import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/swiftserve_app.dart';
import 'firebase_options.dart';
import 'shared/services/client_theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await ClientThemeController.initialize();

  runApp(const SwiftServeApp());
}
