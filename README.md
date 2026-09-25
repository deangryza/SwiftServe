# SwiftServe

This repository contains the mobile app, web dashboard, and backend.

| Component | Directory |
| --- | --- |
| SwiftServe Flutter app | `mobile/my_app/` |
| Web dashboard | `web/swiftserve-login/` |
| Node.js backend | `swiftserve-backend/` |
| Original Flutter starter project | `mobile/` |

## Mobile

```powershell
cd mobile/my_app
flutter pub get
flutter run
```

When opening the repository root in VS Code, select **SwiftServe Mobile** in Run and Debug.
The outer `mobile/` project is a Flutter demo; the SwiftServe app is in `mobile/my_app/`.

## Web dashboard

```powershell
cd web/swiftserve-login
npm ci
npm run dev
```

## Backend

Install dependencies in `swiftserve-backend/` with `npm ci` and start with `node server.js`.
The current Firebase configuration requires a local service account file at
`swiftserve-backend/src/config/serviceAccountKey.json`. Supply this credential locally;
service account files and `.env` files are excluded from Git.

## Repository history

The combined branch preserves the existing mobile `main` and dashboard `master`
histories. Backend files are imported as a snapshot because the original local
backend history included a service account credential.

Deployment services should use the component directories above as their root
directories. Backend credentials must be supplied separately by the deployment environment.
