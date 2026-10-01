# SwiftServe

SwiftServe is organized around one mobile application, one API, and one admin dashboard.

## Active applications

- `mobile/my_app/` — canonical Flutter application for Android and iOS.
- `swiftserve-backend/` — Express API and Firebase Admin integration.
- `admin/` — React/Vite administration dashboard.
- `archive/` — preserved superseded Flutter projects and non-mobile generated targets. Nothing in this directory is an active build root.

## Mobile

```powershell
cd mobile/my_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000
```

Use `http://localhost:5000` for an iOS simulator. Physical devices must use a reachable HTTPS or LAN URL.

## Backend

Copy `swiftserve-backend/.env.example` to `.env`, point `GOOGLE_APPLICATION_CREDENTIALS` at a local service-account file, then run:

```powershell
cd swiftserve-backend
npm install
npm run models:download
npm start
```

Grant admin access with `npm run admin:claim -- grant admin@example.com`. The user must sign in again to refresh the custom claim.

Face verification runs locally in the backend with FaceAPI on TensorFlow.js's WASM backend and makes no external face-comparison API calls. WASM is used because the native TensorFlow binding does not publish a compatible Windows binary for the project's Node 22 runtime. The model weights are not committed; download them with `npm run models:download` after installing dependencies and as part of each deployment build. The server validates and loads all models before accepting requests.

Verification images remain in Firebase Storage while an admin review is pending. Final decisions set Cloud Storage `Custom-Time`; apply `swiftserve-backend/firebase-storage-lifecycle.json` to the Firebase Storage bucket so those objects are deleted after 30 days. The returned `confidence` is a heuristic similarity percentage derived from descriptor distance, not a calibrated probability. Client-side liveness is a deterrent rather than server-attested liveness.

Run verification-rule tests from `mobile/my_app/rules-tests` with `npm install && npm test`. Current Firebase emulators require Java 21 or newer. Apply the retention lifecycle with `gcloud storage buckets update gs://YOUR_BUCKET --lifecycle-file=swiftserve-backend/firebase-storage-lifecycle.json` after reviewing the target bucket.

## Admin

Create `admin/.env` from `admin/.env.example`, register a Firebase Web app for the dashboard, and run:

```powershell
cd admin
npm install
npm run dev
```

Firestore and Storage rules live with the canonical Flutter project. Deploy them from `mobile/my_app` after reviewing the target Firebase project.
