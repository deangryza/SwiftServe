import 'dart:convert';
import 'dart:io';

import 'package:flutter_launcher_icons/main.dart' as launcher;

/// Generate in isolation: 0.14.4 also rewrites unrelated ASSETCATALOG settings.
/// Only launcher resources are copied back; project/manifest files stay intact.
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final previous = Directory.current;
  final staging = Directory.systemTemp.createTempSync(
    'SwiftServeIconGeneration_',
  );
  for (final relative in [
    'pubspec.yaml',
    'flutter_launcher_icons.yaml',
    'assets/app_icon/swiftserve_icon.png',
    'assets/app_icon/swiftserve_foreground.png',
    'android/app/src/main/AndroidManifest.xml',
    'android/app/src/main/res/values/colors.xml',
    'ios/Runner.xcodeproj/project.pbxproj',
  ]) {
    final source = File('${root.path}/$relative');
    if (!source.existsSync()) {
      if (relative.endsWith('colors.xml')) continue;
      throw StateError('Missing icon generation input: $relative');
    }
    final target = File('${staging.path}/$relative');
    target.parent.createSync(recursive: true);
    source.copySync(target.path);
  }
  Directory(
    '${staging.path}/ios/Runner/Assets.xcassets/AppIcon.appiconset',
  ).createSync(recursive: true);
  try {
    Directory.current = staging;
    await launcher.createIconsFromArguments([
      '-f',
      'flutter_launcher_icons.yaml',
    ]);
  } finally {
    Directory.current = previous;
  }

  final allowedAndroid = RegExp(
    r'^android/app/src/main/res/(?:(?:mipmap|drawable)-(?:mdpi|hdpi|xhdpi|xxhdpi|xxxhdpi)/ic_launcher(?:_foreground)?\.png|mipmap-anydpi-v26/ic_launcher\.xml|values/colors\.xml)$',
  );
  final allowedIos = RegExp(
    r'^ios/Runner/Assets\.xcassets/AppIcon\.appiconset/(?:Contents\.json|Icon-App-[\d.x@]+\.png)$',
  );
  final outputs = <String, File>{};
  for (final file in staging.listSync(recursive: true).whereType<File>()) {
    final relative = file.path
        .substring(staging.path.length + 1)
        .replaceAll('\\', '/');
    if (allowedAndroid.hasMatch(relative) || allowedIos.hasMatch(relative)) {
      outputs[relative] = file;
    }
  }
  // Fail before copying partial output if generation failed or is incomplete.
  const catalogPath =
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json';
  final catalogFile = outputs[catalogPath];
  if (catalogFile == null ||
      !outputs.containsKey(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      )) {
    throw StateError('Icon generation incomplete. Inspect ${staging.path}');
  }
  final catalog =
      jsonDecode(catalogFile.readAsStringSync()) as Map<String, dynamic>;
  for (final image in catalog['images'] as List) {
    if (!outputs.containsKey(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/${image['filename']}',
    )) {
      throw StateError('Missing generated iOS image: ${image['filename']}');
    }
  }
  for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
    for (final relative in [
      'android/app/src/main/res/mipmap-$density/ic_launcher.png',
      'android/app/src/main/res/drawable-$density/ic_launcher_foreground.png',
    ]) {
      if (!outputs.containsKey(relative)) {
        throw StateError('Missing generated image: $relative');
      }
    }
  }
  for (final entry in outputs.entries) {
    final target = File('${root.path}/${entry.key}');
    target.parent.createSync(recursive: true);
    if (entry.key == catalogPath) {
      target.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(catalog)}\n',
      );
    } else {
      entry.value.copySync(target.path);
    }
  }
  stdout.writeln('Updated ${outputs.length} Android/iOS icon resources.');
  stdout.writeln(
    'Project and manifest settings preserved. Temporary outputs: ${staging.path}',
  );
}
