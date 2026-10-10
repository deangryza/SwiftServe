# SwiftServe Admin

React/Vite admin dashboard using Firebase Authentication and the SwiftServe backend.

## Local setup

1. Copy `.env.example` to `.env` and fill in your Firebase web app configuration. Use the same Firebase project as the backend. The local backend URL is `VITE_API_BASE_URL=http://localhost:5000`.
2. In `../swiftserve-backend`, run `npm install`, `npm run models:download`, and `npm start`. The backend needs its Firebase application credentials configured.
3. Create or select an existing Firebase Authentication account, then grant access from the backend folder:

   ```powershell
   npm run admin:claim -- grant your-email@example.com
   ```

4. In this folder, run `npm install` and `npm run dev`. Open the URL Vite prints and sign in with that account.

Restart Vite after changing `.env`. Sign out and back in after changing admin claims.

## Backend integration

`src/lib/api.js` sends Firebase bearer tokens to the backend. Worker Verification uses `/api/admin/verifications` to list, inspect, and review worker submissions. The backend requires the `admin: true` custom claim. Dashboard Overview, User Management, Bookings, Reports, Service Categories, Profile, and Notifications now load protected backend data. Pages refresh every 30 seconds. Overview statistics are calculated from Firestore profiles and service requests; Firebase Authentication accounts without a `users` profile are not counted as mobile users.

There are no built-in demo login credentials. Never place a Firebase service-account private key in the frontend or any `VITE_*` variable.

## Data collections and actions

- Users: `users`; suspend/reactivate also updates Firebase Authentication. Worker verification approval stays in the verification review workflow.
- Bookings: `service_requests`; cancellations preserve the mobile status values and require explicit overrides for accepted/ongoing requests.
- Reports: `reports`; empty until real reports are saved. Review updates save status, admin notes, and resolution. Account restrictions use User Management.
- Categories: `service_categories`; empty until categories are added through the admin. Category counts use user and booking category names. Mobile category selectors still need to read this collection to share category management.
- Admin profile: signed-in Firebase Authentication account plus its Firestore profile; password updates reauthenticate with Firebase.
- Notifications: `notifications` filtered to the signed-in admin's recipient ID.

Restart the backend after updating routes. Run `npm test` in the backend and `npm run build` in the admin to verify changes. No demo records are inserted into Firestore.
