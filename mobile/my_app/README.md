# SwiftServe Mobile

The canonical Flutter application targets Android and iOS. Its Dart source uses feature-first folders under `lib/features`, application startup under `lib/app`, and shared models/repositories/services under `lib/shared`.

For a physical Android phone, connected by USB cable or wireless debugging,
start the backend, then run:

```powershell
flutter run
```

The app's default API address is `http://127.0.0.1:5000`. Every Android debug
build runs `adb reverse tcp:5000 tcp:5000` on each connected device (see
`android/app/build.gradle.kts`), so that address reaches the backend on this
computer. If the phone reconnects while the app is running, stop and run
`flutter run` again to restore the forward.

USB checklist: enable Developer options and USB debugging on the phone, accept
the "Allow USB debugging?" prompt, and confirm `adb devices` lists the phone as
`device` (not `unauthorized`).

Rebuild the app when changing `API_BASE_URL`; hot reload does not change this
build-time setting. Debug Android builds allow local HTTP traffic. Release
builds should use a reachable HTTPS backend.

For an Android emulator:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000
```

Firebase project: `swiftserve-production`. Do not replace these files with the archived root project configuration.

## Expired job posts

The backend has an opt-in expiration task for past pending requests with no
applications or booking/history references. It is disabled by default and uses
dry-run mode until explicitly enabled. Eligible jobs are preserved as `expired`,
with an expiration timestamp and one client notification in the same transaction.
Workers cannot apply to expired jobs. The notification and Past bookings open the
original details, where the owning client can choose **Repost Job**. Reposting
prefills the existing form but requires new dates/time and creates a new pending
job ID; the original and its history stay intact. Mobile streams update without
phone timers. Legacy/malformed and ambiguous PHT-midnight schedules are skipped.
See [expiration policy, validation and setup](../../swiftserve-backend/docs/expired-job-cleanup.md).

## Maps and foreground location

SwiftServe uses `flutter_map` with OpenStreetMap tiles for client job pins and
foreground device location for worker-to-job distance. It does not require a
Google Maps API key or a billing-enabled Google Cloud project. The standard
OpenStreetMap tile service is intended for normal interactive viewing only;
do not add bulk downloading or offline prefetching without changing to a tile
provider that explicitly permits it.

The app requests location only while it is open and does not request background
location access. During an ongoing errand, it stores the rider's latest
coordinates in Firestore at
`service_requests/{requestId}/private/rider_location`. That document is readable
only by the request's client and assigned rider under the Firestore rules.

Worker Dashboard Nearby discovery uses a fresh, foreground GPS fix rather than
the saved profile address. Ungranted access is explained before the worker taps
Use My Current Location; denied access has retry/settings actions and never falls
back to the home address. Refresh, reopening Nearby, and returning to it obtain
new coordinates. Search coordinates stay in screen memory and are not written to
the profile. No background location stream is started for discovery.

Nearby includes every eligible physical job within 10 km of its public area
point, nearest first; it excludes own posts, applied-for and unavailable jobs,
invalid pins, and expired explicit start times. Ambiguous legacy midnight starts
remain readable under the existing schedule policy. The current pending-job
Firestore stream is uncapped, so Nearby is not limited to Recent's five cards.
It still downloads all pending posts: large-scale discovery would need a
separately designed geospatial index. Public points are rounded for privacy, so
distances and the 10 km boundary are approximate rather than exact-address GPS
distances. Network failures provide a job-list retry action.

Google sign-in uses Firebase Authentication. Existing profiles retain their client/worker routing; new Google users complete a profile through the existing backend API.

Before testing Google sign-in on Android:

1. In Firebase Authentication > Sign-in method, enable Google and select the support email.
2. In Project settings > Your apps, select Android app `com.example.my_app` and register the signing certificate SHA-1 and SHA-256 fingerprints (debug for local development, release for distribution). Run `./gradlew signingReport` from the `android` directory to view them.
3. Download the updated `google-services.json` into `mobile/my_app/android/app/google-services.json`. It must contain a web OAuth client (`client_type: 3`) for the Google sign-in plugin.
4. Stop and rebuild the Flutter app; hot reload does not update native Firebase configuration.

For iOS/macOS, configure the Firebase Apple app's Google OAuth client and reversed client ID URL scheme following the Google sign-in plugin setup guide. For web, authorize the hosting domain in Firebase Authentication. Windows/Linux native Google sign-in is not supported by this plugin.

Setup references: https://firebase.google.com/docs/auth/flutter/federated-auth and https://pub.dev/packages/google_sign_in_android.


### Firebase-managed expired-job notifications (local only)

The disabled Functions/FCM implementation, demo-emulator setup, billing/platform
requirements and approval-only deployment checklist are documented in
[the activation guide](../../swiftserve-backend/docs/firebase-expired-job-activation.md).
No deployment or production activation follows from installing dependencies.
FCM auto-initialization is off by default. Android/iOS push is an explicit build
opt-in and requires reviewed App Check/APNs/platform setup. Physical delivery is
not verified by the local fake-send tests.
