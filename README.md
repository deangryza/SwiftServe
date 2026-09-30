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
npm start
```

Grant admin access with `npm run admin:claim -- grant admin@example.com`. The user must sign in again to refresh the custom claim.

Face verification uses AWS Rekognition credentials from the backend environment only. Use an IAM policy limited to `rekognition:CompareFaces`, set `AWS_REGION` and `FACE_MATCH_THRESHOLD`, and never place AWS credentials in Flutter configuration.

Verification images remain in Firebase Storage while an admin review is pending. Final decisions set Cloud Storage `Custom-Time`; apply `swiftserve-backend/firebase-storage-lifecycle.json` to the Firebase Storage bucket so those objects are deleted after 30 days. Images are sent to AWS for comparison, and client-side liveness is a deterrent rather than server-attested liveness. Review AWS AI services opt-out settings before production use.

Run verification-rule tests from `mobile/my_app/rules-tests` with `npm install && npm test`. Current Firebase emulators require Java 21 or newer. Apply the retention lifecycle with `gcloud storage buckets update gs://YOUR_BUCKET --lifecycle-file=swiftserve-backend/firebase-storage-lifecycle.json` after reviewing the target bucket.

## Admin

Create `admin/.env` from `admin/.env.example`, register a Firebase Web app for the dashboard, and run:

```powershell
cd admin
npm install
npm run dev
```

Firestore and Storage rules live with the canonical Flutter project. Deploy them from `mobile/my_app` after reviewing the target Firebase project.
