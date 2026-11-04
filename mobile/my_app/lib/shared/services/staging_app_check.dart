import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

Future<bool> requestFreshStagingToken({
  required Future<String?> Function() request,
  required void Function(String) report,
}) async {
  try {
    final token = await request().timeout(const Duration(seconds: 15));
    if (token == null || token.isEmpty) throw StateError('Unavailable');
    report('SwiftServe staging: fresh on-device App Check token acquired.');
    return true;
  } catch (_) {
    report(
      'SwiftServe staging: fresh App Check request failed; check debug registration or retry after backoff.',
    );
    return false;
  }
}

bool stagingAppCheckAllowed({
  required bool requested,
  required String projectId,
  required bool debug,
  required bool android,
  required bool web,
}) {
  if (!requested) return false;
  if (projectId != 'swiftserve-staging-2026' || !debug || !android || web) {
    throw StateError(
      'Staging App Check is restricted to the staging Android debug build.',
    );
  }
  return true;
}

/// Separate from push: do not enable messaging or register a push device here.
Future<void> initializeStagingAppCheck() async {
  if (!stagingAppCheckAllowed(
    requested: const bool.fromEnvironment('STAGING_APP_CHECK_DEBUG'),
    projectId: Firebase.app().options.projectId,
    debug: kDebugMode,
    android: defaultTargetPlatform == TargetPlatform.android,
    web: kIsWeb,
  )) {
    return;
  }
  await FirebaseAppCheck.instance.activate(
    providerAndroid: const AndroidDebugProvider(),
  );
  await requestFreshStagingToken(
    request: () => FirebaseAppCheck.instance.getToken(true),
    report: debugPrint,
  );
}
