# Registration contact availability — local implementation

Client and worker signup now check contact availability after a 650ms typing
pause. Syntactically invalid/empty values do not trigger requests. Checks use
the normalized lowercase email and E.164 phone, including country-code changes.
Duplicate and network-failure feedback appears inline. Registration-only error
themes draw red outlined borders, including focused errors, for name, contact,
address, password, confirmation, and custom-service validation. Valid fields
retain SwiftServe's current colors. The global app error palette is unchanged.

Next flushes pending checks, waits for current results, and validates the form.
Inputs changed while requests are in flight invalidate old responses. Failed
checks never imply availability. Users can retry via Next or the retry icon.
Google setup keeps its own email read-only and checks only the phone, supplying
an ID token so the backend can recognize the authenticated owner's contact.

## Endpoint and integrity

`POST /api/users/registration-availability` accepts exactly `{kind, value}` for
one `email` or `phone` and returns only `{available: boolean}`. It supports
unauthenticated signup, with optional verified Firebase ID tokens for setup of
an existing account. An untrusted body cannot specify an owner UID. The route
is limited to 30 calls per minute per IP and sets `Cache-Control: no-store` on
availability responses. No contact data is added to logs by this controller.

Email lookup uses Firebase Admin Auth's primary email lookup, including accounts
created through Google. Phone lookup checks Firebase Auth, the existing hashed
`phone_number_claims` document, then a limited legacy `users.phoneNumber` query
across both roles. Existing malformed/unowned phone claims remain unavailable;
they are not overwritten or deleted. Only `auth/user-not-found` permits the
lookup to continue as nonexistent. Other errors return 503 without an availability
value. No schema, rules, indexes, authentication-provider configuration or
Firebase enumeration-protection settings were changed.

These checks are advisory, not reservations. Firebase Auth's unique email check
and the existing transactional phone claim at final signup remain authoritative,
including concurrent signups. The existing failed-profile recovery is preserved.

**Privacy tradeoff:** the requested availability response intentionally reveals
whether a supplied contact is in use. The public route must not be treated as an
account-enumeration protection boundary. This implementation limits request rate
and exposes no UID, name, role, sign-in provider, profile or verification status.
The limiter is process-local; multi-instance hosting needs coordinated edge/store
limits. Review trusted-proxy configuration for the chosen host before deployment;
do not blindly trust arbitrary forwarded IP headers. No cloud resources, settings
or production endpoints were deployed or tested here.

Firebase reference: https://firebase.google.com/docs/auth/admin/manage-users

## Testing and local use

Tests run against an isolated source copy with mocked Firebase/Auth and HTTP
lookups. No real emails or phone numbers were queried in production.

```powershell
# swiftserve-backend
node --test test/registrationAvailability.test.js test/userProfile.test.js
node --test

# mobile/my_app
flutter test --no-pub test/registration_contact_fields_test.dart test/registration_availability_flow_test.dart test/worker_register_screen_test.dart test/client_register_screen_test.dart test/registration_address_fields_test.dart
flutter analyze --no-pub lib tool test/registration_contact_fields_test.dart test/registration_availability_flow_test.dart test/worker_register_screen_test.dart
```

Focused backend: 35 passed. Full backend: 167 passed. Focused Flutter: 23 passed.
Final analysis: no issues. Initial analyzer style notices were corrected. Coverage
includes debouncing, stale results, duplicates for either role/provider, phone
normalization and legacy claims, outage/retry behavior, Google setup, input
validation, rate limiting, and both form navigation paths. Full Flutter/emulator
suites and actual device/production lookups were not run for this change.

Restart the local backend to load the route and hot restart Flutter with the
existing API URL/emulator configuration. The backend must have permission to
perform the existing Firebase Admin Auth/user lookups. No IAM changes were made.
If using a USB-connected Android phone and localhost API, retain the established
`adb reverse tcp:5000 tcp:5000` setup. Use dedicated demo/emulator accounts for
manual verification: try a known used email/phone, change them to unused values,
change the country code, simulate a stopped backend, and retry. No actual signup
or profile record changes were performed as part of automated validation.

## Files added or modified

Paths are relative to the repository root; unrelated existing work is preserved.

- `swiftserve-backend/src/controllers/registrationAvailabilityController.js` (new)
- `swiftserve-backend/src/routes/userRoutes.js`
- `swiftserve-backend/test/registrationAvailability.test.js` (new)
- `swiftserve-backend/docs/registration-contact-availability.md` (new)
- `mobile/my_app/lib/shared/services/api_service.dart`
- `mobile/my_app/lib/features/auth/presentation/widgets/registration_contact_fields.dart` (new)
- `mobile/my_app/lib/features/auth/presentation/widgets/registration_validation_theme.dart` (new)
- `mobile/my_app/lib/features/auth/presentation/widgets/phone_number_field.dart`
- `mobile/my_app/lib/features/auth/presentation/screens/client_account_form.dart`
- `mobile/my_app/lib/features/auth/presentation/screens/worker_account_form.dart`
- `mobile/my_app/lib/features/auth/presentation/screens/client_register_screen.dart`
- `mobile/my_app/lib/features/auth/presentation/screens/worker_register_screen.dart`
- `mobile/my_app/lib/features/auth/presentation/screens/google_profile_setup_screen.dart`
- `mobile/my_app/test/registration_contact_fields_test.dart` (new)
- `mobile/my_app/test/registration_availability_flow_test.dart` (new)
- `mobile/my_app/test/worker_register_screen_test.dart`
