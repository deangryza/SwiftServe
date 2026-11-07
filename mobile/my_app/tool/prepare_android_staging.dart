import 'dart:convert';
import 'dart:io';

const stagingProject = 'swiftserve-staging-2026';
const stagingPackage = 'com.example.my_app.staging';

/// Select only the registered staging client, never the first arbitrary client.
Map<String, String> stagingOptions(Map<String, dynamic> config) {
  final project = config['project_info'] as Map<String, dynamic>;
  if (project['project_id'] != stagingProject ||
      project['project_number'] != '856393660184') {
    throw StateError('Unexpected Firebase staging project.');
  }
  final clients = (config['client'] as List)
      .cast<Map<String, dynamic>>()
      .where(
        (client) =>
            client['client_info']['android_client_info']['package_name'] ==
            stagingPackage,
      )
      .toList();
  if (clients.length != 1) {
    throw StateError('Exactly one staging Android client is required.');
  }
  final client = clients.single;
  final appId = client['client_info']['mobilesdk_app_id'];
  final key = (client['api_key'] as List).first['current_key'];
  if (appId != '1:856393660184:android:5ab53b8630b20d3e47d06d' ||
      key is! String ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key)) {
    throw StateError('Unexpected staging app ID or invalid public SDK key.');
  }
  return {
    'apiKey': key,
    'appId': appId as String,
    'messagingSenderId': '856393660184',
    'projectId': stagingProject,
  };
}

String stagingDartOptions(Map<String, String> options) =>
    '''
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('This isolated build supports Android staging only.');
    }
    return android;
  }
  static const android = FirebaseOptions(
${options.entries.map((e) => '    ${e.key}: ${jsonEncode(e.value)},').join('\n')}
  );
}
''';

Future<Directory> prepareStaging(Directory source) async {
  final sdk = File(
    '${source.path}/config/firebase/staging/google-services.json',
  );
  final config = jsonDecode(await sdk.readAsString()) as Map<String, dynamic>;
  final options = stagingOptions(config);
  final gradleSource = File('${source.path}/android/app/build.gradle.kts');
  final gradle = await gradleSource.readAsString();
  const originalId = 'applicationId = "com.example.my_app"';
  if (originalId.allMatches(gradle).length != 1) {
    throw StateError(
      'Android applicationId changed; review staging preparation first.',
    );
  }
  final destination = await Directory.systemTemp.createTemp(
    'SwiftServeAndroidStaging_',
  );
  Future<void> copyDirectory(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list(followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
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
      final target = '${to.path}/$name';
      if (entity is Directory) await copyDirectory(entity, Directory(target));
      if (entity is File) await entity.copy(target);
      // Never follow generated plugin symlinks or copy signing secrets.
    }
  }

  for (final name in ['android', 'lib', 'assets']) {
    await copyDirectory(
      Directory('${source.path}/$name'),
      Directory('${destination.path}/$name'),
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
        .replaceFirst(originalId, 'applicationId = "$stagingPackage"')
        .replaceAll(
          'dependsOn(forwardLocalApi)',
          '// Staging does not forward the production backend port.',
        ),
  );
  final manifest = File(
    '${destination.path}/android/app/src/main/AndroidManifest.xml',
  );
  await manifest.writeAsString(
    (await manifest.readAsString()).replaceFirst(
      'android:label="SwiftServe"',
      'android:label="SwiftServe Staging"',
    ),
  );
  await sdk.copy('${destination.path}/android/app/google-services.json');
  await File(
    '${destination.path}/lib/firebase_options.dart',
  ).writeAsString(stagingDartOptions(options));
  final main = File('${destination.path}/lib/main.dart');
  final mainSource = await main.readAsString();
  const startup = 'await initializeSwiftServeFirebase();';
  if (startup.allMatches(mainSource).length != 1) {
    throw StateError(
      'Firebase startup changed; review staging App Check startup.',
    );
  }
  final stagingMain = mainSource.replaceFirst(
    startup,
    '$startup\n  await initializeStagingAppCheck();',
  );
  await main.writeAsString(
    "import 'shared/services/staging_app_check.dart';\n$stagingMain",
  );
  return destination;
}

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    throw ArgumentError('Run this tool without arguments from mobile/my_app.');
  }
  final directory = await prepareStaging(Directory.current);
  stdout.writeln('Prepared isolated Android staging source: ${directory.path}');
  stdout.writeln('Project: $stagingProject; package: $stagingPackage');
  stdout.writeln(
    'No Firebase deployment, login, token registration or push activation was performed.',
  );
  stdout.writeln('Build from this directory only, with push disabled:');
  stdout.writeln('flutter pub get --offline --enforce-lockfile');
  stdout.writeln(
    'flutter build apk --debug --no-pub --dart-define=ENABLE_PUSH_NOTIFICATIONS=false --dart-define=ENABLE_EXPIRY_PUSH=false --dart-define=STAGING_APP_CHECK_DEBUG=true --dart-define=STAGING_BACKEND=true --dart-define=API_BASE_URL=http://127.0.0.1:5002',
  );
}
