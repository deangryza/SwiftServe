import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../tool/prepare_android_expiry_demo.dart';

void main() {
  test(
    'expiry demo uses separate install and synthetic config, preserving source and secrets',
    () async {
      final source = await Directory.systemTemp.createTemp(
        'ExpiryDemoFixture_',
      );
      Future<void> put(String path, String text) async {
        final file = File('${source.path}/$path');
        await file.parent.create(recursive: true);
        await file.writeAsString(text);
      }

      await put(
        'android/app/build.gradle.kts',
        'applicationId = "com.example.my_app"\ndependsOn(forwardLocalApi)',
      );
      await put(
        'android/app/src/main/AndroidManifest.xml',
        '<application android:label="SwiftServe"/>',
      );
      await put(
        'android/app/google-services.json',
        'real config must not be copied',
      );
      await put(
        'android/app/src/debug/google-services.json',
        'alternate real config',
      );
      await put('android/key.properties', 'private signing data');
      await put('android/private.keystore', 'private signing key');
      await put('lib/firebase_options.dart', 'original production options');
      await put('assets/asset.txt', 'kept');
      for (final file in [
        'pubspec.yaml',
        'pubspec.lock',
        'analysis_options.yaml',
      ]) {
        await put(file, 'fixture');
      }
      final result = await prepareExpiryDemo(source);
      expect(
        await File('${source.path}/lib/firebase_options.dart').readAsString(),
        'original production options',
      );
      expect(
        await File(
          '${source.path}/android/app/google-services.json',
        ).readAsString(),
        'real config must not be copied',
      );
      final config =
          jsonDecode(
                await File(
                  '${result.path}/android/app/google-services.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(config['project_info']['project_id'], 'demo-swiftserve-cleanup');
      expect(
        config['client'][0]['client_info']['android_client_info']['package_name'],
        expiryDemoPackage,
      );
      expect(
        await File(
          '${result.path}/android/app/src/debug/google-services.json',
        ).exists(),
        isFalse,
      );
      expect(
        await File('${result.path}/android/key.properties').exists(),
        isFalse,
      );
      expect(
        await File('${result.path}/android/private.keystore').exists(),
        isFalse,
      );
      expect(
        await File('${result.path}/lib/firebase_options.dart').readAsString(),
        contains('cloud fallback is disabled'),
      );
      expect(
        await File(
          '${result.path}/android/app/build.gradle.kts',
        ).readAsString(),
        contains(expiryDemoPackage),
      );
      expect(
        await File(
          '${result.path}/android/app/src/main/AndroidManifest.xml',
        ).readAsString(),
        contains('SwiftServe Expiry Demo'),
      );
    },
  );
}
