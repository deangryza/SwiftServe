import 'dart:convert';
import 'dart:io';

const expiryDemoPackage = 'com.example.my_app.expiry_demo';

/// A side-by-side install: never replace the real/staging app or native config.
Future<Directory> prepareExpiryDemo(Directory source) async {
  final gradle = await File(
    '${source.path}/android/app/build.gradle.kts',
  ).readAsString();
  const originalId = 'applicationId = "com.example.my_app"';
  if (originalId.allMatches(gradle).length != 1) {
    throw StateError(
      'Review the Android application ID before preparing a demo.',
    );
  }
  final destination = await Directory.systemTemp.createTemp(
    'SwiftServeExpiryAndroid_',
  );
  Future<void> copy(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final item in from.list(followLinks: false)) {
      final name = item.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if ([
            '.git',
            '.gradle',
            '.dart_tool',
            'build',
            'node_modules',
            'key.properties',
            'google-services.json',
          ].contains(name) ||
          name.startsWith('.env') ||
          name.endsWith('.jks') ||
          name.endsWith('.keystore') ||
          name.toLowerCase().contains('serviceaccount')) {
        continue;
      }
      if (item is Directory) await copy(item, Directory('${to.path}/$name'));
      if (item is File) await item.copy('${to.path}/$name');
    }
  }

  for (final folder in ['android', 'lib', 'assets']) {
    await copy(
      Directory('${source.path}/$folder'),
      Directory('${destination.path}/$folder'),
    );
  }
  for (final name in [
    'pubspec.yaml',
    'pubspec.lock',
    'analysis_options.yaml',
  ]) {
    await File('${source.path}/$name').copy('${destination.path}/$name');
  }
  await File('${destination.path}/android/app/build.gradle.kts').writeAsString(
    gradle
        .replaceFirst(originalId, 'applicationId = "$expiryDemoPackage"')
        .replaceAll(
          'dependsOn(forwardLocalApi)',
          '// Demo does not forward the real API port.',
        ),
  );
  final manifest = File(
    '${destination.path}/android/app/src/main/AndroidManifest.xml',
  );
  await manifest.writeAsString(
    (await manifest.readAsString()).replaceFirst(
      'android:label="SwiftServe"',
      'android:label="SwiftServe Expiry Demo"',
    ),
  );
  // Public synthetic native options only; the Dart bootstrap selects the emulators.
  await File(
    '${destination.path}/android/app/google-services.json',
  ).writeAsString(
    jsonEncode({
      'project_info': {
        'project_number': '000000000000',
        'project_id': 'demo-swiftserve-cleanup',
      },
      'client': [
        {
          'client_info': {
            'mobilesdk_app_id': '1:000000000000:android:demo',
            'android_client_info': {'package_name': expiryDemoPackage},
          },
          'api_key': [
            {'current_key': 'demo-swiftserve-api-key'},
          ],
        },
      ],
      'configuration_version': '1',
    }),
  );
  await File('${destination.path}/lib/firebase_options.dart').writeAsString('''
import 'package:firebase_core/firebase_core.dart';
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => throw StateError(
    'Expiry demo requires LOCAL_FIREBASE_EMULATOR_HOST; cloud fallback is disabled.');
}
''');
  return destination;
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    throw ArgumentError('Run without arguments from mobile/my_app.');
  }
  final result = await prepareExpiryDemo(Directory.current);
  stdout.writeln('Prepared side-by-side Android demo: ${result.path}');
  stdout.writeln(
    'Package: $expiryDemoPackage; no production or staging config changed.',
  );
  stdout.writeln('From the prepared directory:');
  stdout.writeln('flutter pub get --offline --enforce-lockfile');
  stdout.writeln(
    'flutter run --debug --dart-define=LOCAL_FIREBASE_EMULATOR_HOST=127.0.0.1 --dart-define=API_BASE_URL=http://127.0.0.1:5006 --dart-define=ENABLE_PUSH_NOTIFICATIONS=false --dart-define=ENABLE_EXPIRY_PUSH=false',
  );
}
