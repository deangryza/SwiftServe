# SwiftServe launcher artwork

The supplied `swiftserve_peeking_mascot_with_wrench.png` is a 2720 × 1480
preview sheet. Only its large main icon was extracted at `(200, 160)`, size
1120 × 1120. Labels and the smaller previews are not part of the launcher icon.
No artwork was redrawn or recolored.

- `swiftserve_logo.png`: extracted artwork with its original transparency.
- `swiftserve_icon.png`: 1024 ? 1024 opaque canvas with artwork filling the full
  width and height. Transparent corners are composited over `#FFD539`, sampled
  from the original logo at `(560, 112)`, rather than over white.
- `swiftserve_foreground.png`: 1024 ? 1024 transparent adaptive-layer canvas.
  Artwork spans 682? ? 682? pixels, matching Android's central 72/108 viewport.
  Combined with the same yellow background, this fills the visible launcher icon
  without the previous white border. Foreground inset remains zero.

The original artwork is not redrawn or recolored; only transparent areas are
backed with an existing logo color. iOS assets remain opaque. No monochrome
variant is configured. Unlike the previous padded version, this full-bleed
layout intentionally extends beyond Android's conservative 66/108 safe circle.
The launcher's normal circle/squircle mask can trim artwork at the outer corners.

From `mobile/my_app`:

```powershell
flutter pub get
dart run tool/generate_app_icons.dart
```

Use this wrapper instead of invoking the generator directly: version 0.14.4
rewrites every matching `ASSETCATALOG` setting in an Xcode configuration, including
the unrelated Swift asset-symbol setting. The wrapper generates in a temporary
directory, verifies expected outputs, and copies back only Android icon resources
and the iOS AppIcon catalog. It preserves the manifest and Xcode project. Existing
`@mipmap/ic_launcher` and `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` references
already select these assets. No runtime Flutter asset declaration is needed.

After changing native icons, stop the running app and rebuild with `flutter run`.
Hot reload/hot restart alone does not rebuild native launcher resources. Launchers
may cache icons; verify after the updated app is installed. Avoid uninstalling
an existing install merely to refresh its icon, because uninstalling removes local
app data.

Windows can check the generated iOS catalog, dimensions and PNG opacity, but an
iOS build and home-screen verification still require Xcode/macOS and an iOS
simulator or device. Android home-screen/launcher verification also requires
installing the rebuilt app. No production resources or installed apps are changed
by icon generation itself.

## Local verification

- Extracted artwork matches the supplied main-icon crop pixel-for-pixel.
- 25 iOS catalog entries reference 21 correctly sized RGB PNGs without alpha,
  including the 1024px App Store icon.
- Five Android legacy sizes: 48, 72, 96, 144, 192px.
- Five Android adaptive foreground sizes: 108, 162, 216, 324, 432px.
- Full-bleed adaptive artwork spans the central 72/108 viewport; the yellow
  background fills transparent corners. The former 66/108 safe-area guarantee
  applies only to the previous padded version, not this full-bleed layout.
- Android AAPT2 36.1.0 compiled and linked all resources against android-36.
  This was a resource-only check, not a full APK build or device installation.
- `flutter pub get --offline --enforce-lockfile` passed in the isolated copy.
- `flutter analyze --no-pub lib tool/generate_app_icons.dart`: no issues.
- Safe generator preserved the Android manifest and Xcode project byte-for-byte.
- Legacy, circular adaptive and iOS source previews were visually inspected.

The full Flutter suite was not rerun for this native-asset-only change. iOS
compilation and physical-device home-screen checks remain unverified. No installed
apps, production services, Firebase configuration or app functionality were changed.

Generator documentation: https://pub.dev/packages/flutter_launcher_icons

## Files added or updated for this task

Paths below are relative to `mobile/my_app`; unrelated pre-existing changes are
not included. Native resources total 34 files. The manifest and Xcode project
are deliberately absent because their existing icon references were retained.

- `android/app/src/main/res/drawable-hdpi/ic_launcher_foreground.png`
- `android/app/src/main/res/drawable-mdpi/ic_launcher_foreground.png`
- `android/app/src/main/res/drawable-xhdpi/ic_launcher_foreground.png`
- `android/app/src/main/res/drawable-xxhdpi/ic_launcher_foreground.png`
- `android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png`
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- `android/app/src/main/res/mipmap-hdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-mdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`
- `android/app/src/main/res/values/colors.xml`
- `assets/app_icon/README.md`
- `assets/app_icon/swiftserve_foreground.png`
- `assets/app_icon/swiftserve_icon.png`
- `assets/app_icon/swiftserve_logo.png`
- `flutter_launcher_icons.yaml`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-50x50@1x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-50x50@2x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-57x57@1x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-57x57@2x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-72x72@1x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-72x72@2x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png`
- `pubspec.lock`
- `pubspec.yaml`
- `tool/generate_app_icons.dart`
