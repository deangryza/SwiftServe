# Registration birthday and minimum age

Local implementation only; no deployment, production data changes, or rules changes.

- Both registration roles require Birthday on a separate Birthday and Location
  step after the name fields and before credentials, using Flutter's calendar-only
  date picker. Future dates are unavailable. The earliest
  supported date is January 1, 1900.
- Age is checked using month/day/year against today's Philippine calendar date.
  Exactly 18 is eligible. February 29 birthdays reach the next age on March 1 in
  a non-leap year. This is an explicit product convention, not a legal determination.
- Email registration validates before Firebase Auth signup. Google profile setup
  validates before submitting a profile; Google authentication already exists at
  that point. Both flows validate again at final submission, independent of which
  wizard page is mounted. API submission and saved-draft retry validate too.
- Wire/storage format: `dateOfBirth: "YYYY-MM-DD"`, a date only, with no timezone
  conversion. Store it in `users/{uid}` only. It is not copied to public or worker
  discovery profiles. Drafts retain it for interrupted profile setup. Legacy drafts
  without a birthday require selection on the retry screen; existing completed
  user profiles are not migrated or newly blocked.
- `POST /api/users/profile` independently checks the birthday using server time,
  before database queries, photo decoding, or profile/phone-claim writes. It returns
  400 for missing/malformed/future dates, 403 `UNDERAGE_REGISTRATION` for under 18.
  The error message is:
  "You are not eligible to use SwiftServe. You must be at least 18 years old to create an account."
- Local Firestore rules already deny client creation of `users` records and exclude
  birthday from self-update fields. No rules edits were needed. Public-profile
  client creation is separately allowed by existing rules: it does not create the
  private account profile consumed by AuthGate. This is not an all-collection age
  authorization policy. Do not assume every authenticated-only operation enforces age.

## Remaining security boundaries

This enforces a **declared** birthday, not identity/age proof. A caller can lie about
their birthday. Firebase client email signup and Google sign-in can also create an
Auth-only account outside the app; the profile endpoint rejects underage birthdays,
but no blocking Auth trigger or custom server-owned signup has been deployed.
Preventing every Auth-only signup and applying age eligibility to every database
operation requires a separately reviewed authentication/rules design. Do not claim
that frontend validation or these endpoint checks provide verified-age assurance.

Old clients that omit birthday will be rejected by an updated backend. Coordinate
client/backend rollout before deployment. Existing Admin SDK scripts bypass this
HTTP endpoint and remain privileged; do not run them on real registrations to bypass
the policy. No existing records were backfilled. Restart the local backend and
rebuild/hot restart the app to test these local changes.

## Local synthetic tests

From `swiftserve-backend`:

```powershell
node --test test/registrationBirthday.test.js test/userProfile.test.js
```

From `mobile/my_app`:

```powershell
flutter test --no-pub test/registration_birthday_test.dart
flutter analyze --no-pub
```

No Firebase credentials or live data are needed for these tests. Android picker
behavior is widget-tested; physical Android interaction must still be checked.

## Actual validation results

- Backend command above: 33 passed, 0 failed (in-memory Firebase replacement).
- Focused Flutter birthday suite: 5 passed, 0 failed.
- Flutter analyze: no issues after correcting an initial test assertion and two lint findings.
- Broader Flutter command:

```powershell
flutter test --no-pub test/registration_availability_flow_test.dart test/client_register_screen_test.dart test/worker_register_screen_test.dart test/federated_account_form_test.dart test/profile_identity_test.dart test/worker_service_selector_test.dart test/registration_address_fields_test.dart test/registration_contact_fields_test.dart test/client_account_form_test.dart
```

Result: 39 passed, 4 failed. All four are the previously reproduced client-form
navigation failures (320, 390, 768, and 1440 widths) expecting `Enter code` without
mocking the required contact-availability HTTP lookup. The fixtures now supply an
adult birthday; those unrelated availability failures were not hidden or fixed.
An SVG filter warning also appeared during the dashboard test, which passed.
No emulator, live Firebase, physical device, or native APK build was run for this task.

## Changed files

Paths relative to the repository root:

```text
mobile/my_app/lib/features/auth/presentation/screens/client_account_form.dart
mobile/my_app/lib/features/auth/presentation/screens/client_register_screen.dart
mobile/my_app/lib/features/auth/presentation/screens/google_profile_setup_screen.dart
mobile/my_app/lib/features/auth/presentation/screens/profile_completion_screen.dart
mobile/my_app/lib/features/auth/presentation/screens/worker_account_form.dart
mobile/my_app/lib/features/auth/presentation/widgets/registration_birthday_field.dart
mobile/my_app/lib/shared/services/api_service.dart
mobile/my_app/lib/shared/services/profile_draft_store.dart
mobile/my_app/lib/shared/utils/registration_birthday.dart
mobile/my_app/test/client_account_form_test.dart
mobile/my_app/test/client_register_screen_test.dart
mobile/my_app/test/federated_account_form_test.dart
mobile/my_app/test/profile_identity_test.dart
mobile/my_app/test/registration_availability_flow_test.dart
mobile/my_app/test/registration_birthday_test.dart
mobile/my_app/test/worker_register_screen_test.dart
mobile/my_app/test/worker_service_selector_test.dart
swiftserve-backend/docs/registration-birthday.md
swiftserve-backend/scripts/testStagingOnboarding.js
swiftserve-backend/src/controllers/userController.js
swiftserve-backend/src/services/registrationBirthday.js
swiftserve-backend/test/registrationBirthday.test.js
swiftserve-backend/test/userProfile.test.js
```

Existing synthetic registration fixtures gained a valid birthday; the staging test
script was updated locally but was not run against staging. Existing staged work
was retained; these changes were not staged, committed, pushed, or deployed.
