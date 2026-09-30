# SwiftServe Mobile

The canonical Flutter application targets Android and iOS. Its Dart source uses feature-first folders under `lib/features`, application startup under `lib/app`, and shared models/repositories/services under `lib/shared`.

Provide the profile API URL at build time:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000
```

Firebase project: `swiftserve-production`. Do not replace these files with the archived root project configuration.
