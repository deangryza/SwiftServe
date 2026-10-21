# SwiftServe Mobile

The canonical Flutter application targets Android and iOS. Its Dart source uses feature-first folders under `lib/features`, application startup under `lib/app`, and shared models/repositories/services under `lib/shared`.

Provide the profile API URL at build time:

For a physical Android phone connected by USB, start the backend, then run:

```powershell
adb reverse tcp:5000 tcp:5000
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:5000
```

Repeat `adb reverse` after reconnecting the phone. Keep USB connected while using
the local API. Rebuild the app when changing `API_BASE_URL`; hot reload does not
change this build-time setting. Debug Android builds allow local HTTP traffic.
Release builds should use a reachable HTTPS backend.

The default API address is `http://127.0.0.1:5000`. Both VS Code mobile launch
configurations automatically forward port 5000 through ADB before launching.

For an Android emulator:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000
```

Firebase project: `swiftserve-production`. Do not replace these files with the archived root project configuration.

## Maps and foreground location

SwiftServe uses `flutter_map` with OpenStreetMap tiles for client job pins and
foreground device location for worker-to-job distance. It does not require a
Google Maps API key or a billing-enabled Google Cloud project. The standard
OpenStreetMap tile service is intended for normal interactive viewing only;
do not add bulk downloading or offline prefetching without changing to a tile
provider that explicitly permits it.

The app requests location only while it is open. It does not persist worker
coordinates or request background location access.

Google sign-in uses Firebase Authentication. Existing profiles retain their client/worker routing; new Google users complete a profile through the existing backend API.

Before testing Google sign-in on Android:

1. In Firebase Authentication > Sign-in method, enable Google and select the support email.
2. In Project settings > Your apps, select Android app `com.example.my_app` and register the signing certificate SHA-1 and SHA-256 fingerprints (debug for local development, release for distribution). Run `./gradlew signingReport` from the `android` directory to view them.
3. Download the updated `google-services.json` into `mobile/my_app/android/app/google-services.json`. It must contain a web OAuth client (`client_type: 3`) for the Google sign-in plugin.
4. Stop and rebuild the Flutter app; hot reload does not update native Firebase configuration.

For iOS/macOS, configure the Firebase Apple app's Google OAuth client and reversed client ID URL scheme following the Google sign-in plugin setup guide. For web, authorize the hosting domain in Firebase Authentication. Windows/Linux native Google sign-in is not supported by this plugin.

Setup references: https://firebase.google.com/docs/auth/flutter/federated-auth and https://pub.dev/packages/google_sign_in_android.
