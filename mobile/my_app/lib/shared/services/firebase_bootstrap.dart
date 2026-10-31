import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

/// Explicit debug-only demo project. Never redirects the production project.
Future<void> initializeSwiftServeFirebase() async {
  const host = String.fromEnvironment('LOCAL_FIREBASE_EMULATOR_HOST');
  if (host.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    return;
  }
  if (!kDebugMode ||
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.android ||
      !['127.0.0.1', 'localhost', '10.0.2.2'].contains(host)) {
    throw StateError(
      'Only debug loopback/Android emulator Firebase is supported.',
    );
  }
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'demo-swiftserve-api-key',
      appId: '1:000000000000:android:demo',
      messagingSenderId: '000000000000',
      projectId: 'demo-swiftserve-cleanup',
    ),
  );
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8187);
  FirebaseFunctions.instanceFor(
    region: 'us-central1',
  ).useFunctionsEmulator(host, 5001);
}
