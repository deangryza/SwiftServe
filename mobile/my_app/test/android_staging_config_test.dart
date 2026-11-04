import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../tool/prepare_android_staging.dart';

void main() {
  Map<String, dynamic> fixture() => {
    'project_info': {
      'project_id': stagingProject,
      'project_number': '856393660184',
    },
    'client': [
      {
        'client_info': {
          'mobilesdk_app_id': 'wrong',
          'android_client_info': {'package_name': 'com.example.my_app'},
        },
        'api_key': [
          {'current_key': 'wrong'},
        ],
      },
      {
        'client_info': {
          'mobilesdk_app_id': '1:856393660184:android:5ab53b8630b20d3e47d06d',
          'android_client_info': {'package_name': stagingPackage},
        },
        'api_key': [
          {'current_key': 'public-test-key'},
        ],
      },
    ],
  };
  test('selects exact staging client instead of production client', () {
    final options = stagingOptions(fixture());
    expect(options['apiKey'], 'public-test-key');
    expect(options['projectId'], stagingProject);
    expect(
      stagingDartOptions(options),
      isNot(contains('swiftserve-production')),
    );
  });
  test('rejects wrong project and ambiguous or missing staging clients', () {
    final config = fixture();
    config['project_info']['project_id'] = 'swiftserve-production';
    expect(() => stagingOptions(config), throwsStateError);
    final duplicate = fixture();
    (duplicate['client'] as List).add(duplicate['client'][1]);
    expect(() => stagingOptions(duplicate), throwsStateError);
    final missing = fixture();
    (missing['client'] as List).removeLast();
    expect(() => stagingOptions(missing), throwsStateError);
  });
  test('downloaded SDK config targets only registered staging app', () {
    final config =
        jsonDecode(
              File(
                'config/firebase/staging/google-services.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(stagingOptions(config)['projectId'], stagingProject);
  });
  test(
    'preparation preserves source and excludes alternate native configs and signing secrets',
    () async {
      final source = await Directory.systemTemp.createTemp(
        'SwiftServeStagingFixture_',
      );
      Future<void> put(String path, String content) async {
        final file = File('${source.path}/$path');
        await file.parent.create(recursive: true);
        await file.writeAsString(content);
      }

      await put(
        'config/firebase/staging/google-services.json',
        jsonEncode(fixture()),
      );
      await put(
        'android/app/build.gradle.kts',
        'applicationId = "com.example.my_app"\ndependsOn(forwardLocalApi)',
      );
      await put(
        'android/app/src/main/AndroidManifest.xml',
        '<application android:label="SwiftServe"/>',
      );
      await put('android/app/src/debug/google-services.json', 'must-not-copy');
      await put('android/key.properties', 'must-not-copy');
      await put('android/test.keystore', 'must-not-copy');
      await put('lib/firebase_options.dart', 'original-production-options');
      await put(
        'lib/main.dart',
        'Future<void> main() async { await initializeSwiftServeFirebase(); }',
      );
      await put('assets/marker.txt', 'asset');
      for (final name in [
        'pubspec.yaml',
        'pubspec.lock',
        'analysis_options.yaml',
      ]) {
        await put(name, 'fixture');
      }
      final output = await prepareStaging(source);
      expect(
        File('${source.path}/lib/firebase_options.dart').readAsStringSync(),
        'original-production-options',
      );
      expect(
        File('${source.path}/android/app/build.gradle.kts').readAsStringSync(),
        contains('applicationId = "com.example.my_app"'),
      );
      expect(
        File('${output.path}/lib/firebase_options.dart').readAsStringSync(),
        contains(stagingProject),
      );
      expect(
        File('${output.path}/android/app/build.gradle.kts').readAsStringSync(),
        contains(stagingPackage),
      );
      expect(
        File(
          '${output.path}/android/app/src/debug/google-services.json',
        ).existsSync(),
        isFalse,
      );
      expect(
        File('${output.path}/android/key.properties').existsSync(),
        isFalse,
      );
      expect(
        File('${output.path}/android/test.keystore').existsSync(),
        isFalse,
      );
      expect(
        jsonDecode(
          File(
            '${output.path}/android/app/google-services.json',
          ).readAsStringSync(),
        )['project_info']['project_id'],
        stagingProject,
      );
    },
  );
}
