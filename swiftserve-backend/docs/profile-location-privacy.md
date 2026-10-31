# Residential location privacy — local changes

This implementation is local only. No production records were read or changed,
no rules or configuration were edited, and nothing was staged or deployed.

## Behavior

- Public Client and Worker profiles, user search results and recommended-worker
  cards use one safe formatter. The example `123 Example Street, Brgy. Ligas,
  Malolos, Bulacan` displays as **Brgy. Ligas, Malolos**.
- A known city with no usable barangay displays only that city. Province, street,
  house/unit numbers, subdivisions and landmarks are not copied into the label.
- Unknown or ambiguous legacy strings display **Location not provided**. In
  particular, unlabelled comma-separated strings are not guessed to contain a
  barangay/city: the same positions can contain a subdivision or landmark.
- Both languages share test vectors, including numeric/alphanumeric barangays,
  Unicode names, malformed components and fallback behavior.
- Public profile searches match the reduced locality, not the raw address.
  Typing someone's street/house number does not discover them via `location`.
- Nearby discovery geocodes only recognized barangay/city labels, including the
  client's saved-area origin. Current-location GPS still works and is not
  published as a residential profile. Unknown locations produce suggestions
  without invented distances. Distances/radius remain approximate area-based
  estimates, not a guarantee about the person's exact home.

Private `users/{uid}.address` remains available to its owner under existing
rules. Personal edit screens still show that owner's own address. Job pickup,
drop-off and authorized booking navigation are separate location workflows and
were not changed. Self-authored bios, names, skills, chat messages and job text
are not analyzed for voluntarily disclosed personal information.

## Writers and compatibility

The backend no longer copies `users.address` verbatim into public collections:

- Creating either role writes the general locality to `public_profiles` and, for
  workers, `worker_profiles`.
- Adding/switching roles and the backend photo endpoint refresh those public
  location fields without resetting private addresses, verification or ratings.
- Public documents gain two optional components, `barangay` and
  `cityMunicipality`, alongside the existing coarse `location` string. These are
  backend-written fields; no new collections, dependencies or indexes are needed.
- The structured address form now includes an explicit `Brgy.` component in its
  saved string. It strips duplicate labels when reopening; street/province remain
  private. Untouched existing addresses are not automatically rewritten.
- Existing public photo/name edits remain compatible with the current rules:
  the emulator tests verify that backend locality components survive those edits.

Address edits now use authenticated `POST /api/users/profile/address`. The
backend derives the public label from the submitted private address and updates
`users`, `public_profiles`, and any existing `worker_profiles` document in one
Firestore transaction. The authenticated UID determines the target; supplied
UIDs, public labels, roles and verification fields are ignored. Ratings, photos,
verification and unrelated profile fields are preserved. Public documents receive
only `location`, `barangay`, and `cityMunicipality` location fields, never the full
address or province. Unsupported address formats are rejected before writing.

Both roles share this edit screen. Address changes require the backend to be
reachable; restart the backend with the new route/controller before testing.
An unavailable backend fails the save instead of leaving a private-only update.
Name-only and photo edits retain the existing flow. No security rules were changed.
This does not backfill old accounts: previously stale public areas are refreshed
when the owner next edits their address through the updated app.

### Public About editing

The shared client/worker edit screen now has an optional, multiline **About**
field above the address, limited to 500 characters and labelled as publicly
visible. It uses the existing `description` field. Changed descriptions use
authenticated `POST /api/users/profile/details`, sharing the transactional
handler with the address endpoint. A save can contain About, address, or both;
omitting an unchanged field preserves it. About-only saves do not require
rewriting legacy address data. Supplied target UIDs and authorization fields
remain ignored; the token UID owns the affected documents.

The transaction merges description into the private user, public profile and
any existing worker profile. It never creates a worker account for a client.
An empty description clears About; public rendering treats an existing
`description` key as authoritative, including empty text, so an obsolete
`bio`/`about` alias cannot reappear. Legacy aliases remain a display fallback
when `description` is absent. No rules, collections, dependencies or indexes
were changed. Restart the backend and hot restart Flutter before device testing.

Local isolated validation: focused backend 53 passed; full backend 156 passed;
focused Flutter About/API/search/identity suite 14 passed. Initial analysis found
two null-aware-element style notices, corrected before revalidation. Final
`flutter analyze --no-pub` found no issues; all five API tests passed again
after that syntax adjustment. No real
Firebase or physical-device writes were tested. Manual check: edit About in each
role, view from another account, update About and address together, and clear
About; verify public text, general location, ratings and verification.

### Address synchronization follow-up validation

Tests ran against an isolated local source copy, with no production access:

- `node --test test/userProfile.test.js test/publicProfileLocation.test.js`: 49 passed.
- Complete backend `node --test`: 152 passed, zero failures. No Firestore emulator
  was running; this does not verify real Firebase transactions or device behavior.
- `flutter test --no-pub test/profile_address_api_test.dart test/public_profile_location_test.dart test/public_profile_search_test.dart test/registration_address_fields_test.dart test/worker_discovery_test.dart`: 59 passed.
- `flutter analyze --no-pub`: no issues.

Initial broader backend attempts failed because the isolated copy lacked shared
Functions source and backend scripts; including those dependencies resolved the
test-harness errors. No source changes were made to hide those failures.

Follow-up files: `src/controllers/userController.js`, `src/routes/userRoutes.js`,
`test/userProfile.test.js`, this document, and Flutter's
`lib/features/client/presentation/screens/client_profile_screen.dart`,
`lib/shared/services/api_service.dart`, `test/profile_address_api_test.dart`.

Manual verification: restart the backend and hot restart Flutter; edit a client
address, save, then view that account from a different signed-in account. Expect
`Brgy. <barangay>, <city/municipality>` without street/province. Repeat for a
worker/dual-role account and check discovery. With the backend stopped, a changed
address should show a save error and leave both old records unchanged. Device
checks and live Firebase behavior have not been verified here. No rules changed,
no deployment, staging or commit was performed.

## Important unresolved storage boundary

**Formatting is not a Firestore access-control boundary.** Existing
`public_profiles` and `worker_profiles` documents may still contain old full
addresses. Current rules let signed-in users download those documents, including
through an older app or a direct SDK request. The new UI masks recognized legacy
addresses, but it cannot erase already published data or revoke old copies.

One emulator characterization test deliberately demonstrates that an existing
raw public address remains readable. Its passing result documents an unresolved
exposure; it must not be presented as proof that all stored data is private.
No live database was inspected, so the number of affected records is unknown.

The scope-specific security-rules audit (local inspection only) is:

```json
{
  "score": 3,
  "summary": "Public displays and new backend writes are reduced to locality; existing public documents still require approved cleanup and policy review.",
  "findings": [
    {
      "check": "Public document data minimization",
      "severity": "moderate",
      "issue": "Signed-in readers can fetch legacy location strings verbatim from either public collection.",
      "recommendation": "Approve a reviewed, conflict-safe backfill of public location fields; keep exact addresses solely in owner-protected records."
    },
    {
      "check": "Worker profile update bypass",
      "severity": "moderate",
      "issue": "The existing worker_profiles self-write rule does not restrict address/location field changes beyond preserving verificationStatus.",
      "recommendation": "Review a field allowlist and backend-managed public location policy before changing rules; do not rely on UI validation for storage privacy."
    }
  ]
}
```

## Steps requiring human approval before live privacy can be claimed

1. Review and roll out the updated app/backend; the already running Node server
   does not hot-reload these controller changes. No server was restarted here.
2. Approve read-only inventory/dry-run access to the intended project/database.
   Do not print or export exact addresses into ordinary logs or Git.
3. Review only the proposed public-field updates, keyed by stable account UID.
   Use recognized explicit components; redact unknown formats rather than guess.
   Preserve all ratings, photos, roles, verification, reviews and private records.
4. Approve a transactional/preconditioned backfill of `location`, `barangay` and
   `cityMunicipality` in both public collections. Check update times so a retry
   cannot overwrite a newer public projection. Retain a protected rollback copy;
   never roll back by republishing residential addresses to public collections.
   If inventory finds other residential fields, separately review removing their
   public copies; cleaning `location` alone must not be assumed sufficient.
5. Separately review rule changes preventing old/direct clients from publishing
   residential fields again. Firestore cannot hide individual document fields:
   sensitive fields must live in owner-protected documents. No rule deployment
   is authorized by this local implementation.
6. Verify the live public payloads, old/new app compatibility, owner edits and
   nearby matching after that rollout. Existing copies/caches cannot be recalled
   by changing the UI. Hot-restart a development app to clear old in-memory
   geocoding caches when testing this change.

Expiration/push gates and all production Firebase configuration stay unchanged.

## Reproduce locally

Use the installed dependencies and Node 22. From `mobile/my_app`:

```powershell
flutter test --no-pub test/public_profile_location_test.dart test/public_profile_search_test.dart test/registration_address_fields_test.dart test/worker_discovery_test.dart test/profile_identity_test.dart
flutter analyze --no-pub
```

From `swiftserve-backend` (fake database; no live access):

```powershell
node --test test/publicProfileLocation.test.js test/userProfile.test.js
```

From the repository root, using the existing loopback emulator configuration:

```powershell
node mobile/my_app/rules-tests/node_modules/firebase-tools/lib/bin/firebase.js emulators:exec --project demo-swiftserve-privacy --config mobile/my_app/firebase.local.json --only firestore "node --test mobile/my_app/rules-tests/profile-location-privacy.rules.test.js"
```

No production configuration or credentials are required for those tests. The
Firestore suite tests projections produced by the actual backend helper, other
users' denied private reads, owner-only edits and the unresolved legacy exposure.

## File inventory

Modified existing files (all pre-existing edits preserved):

- `mobile/my_app/lib/features/auth/presentation/widgets/registration_address_fields.dart`
- `mobile/my_app/lib/features/client/presentation/screens/client_search_screen.dart`
- `mobile/my_app/lib/features/client/presentation/widgets/nearby_workers_section.dart`
- `mobile/my_app/lib/features/worker/presentation/screens/worker_search_screen.dart`
- `mobile/my_app/lib/shared/models/discovered_worker.dart`
- `mobile/my_app/lib/shared/screens/public_profile_screen.dart`
- `mobile/my_app/lib/shared/services/worker_discovery_service.dart`
- `mobile/my_app/test/nearby_workers_section_test.dart`
- `mobile/my_app/test/public_profile_search_test.dart`
- `mobile/my_app/test/registration_address_fields_test.dart`
- `mobile/my_app/test/worker_discovery_test.dart`
- `swiftserve-backend/src/controllers/userController.js`
- `swiftserve-backend/test/userProfile.test.js`

Added files:

- `mobile/my_app/lib/shared/utils/public_profile_location.dart`
- `mobile/my_app/rules-tests/profile-location-privacy.rules.test.js`
- `mobile/my_app/test/fixtures/public_profile_locations.json`
- `mobile/my_app/test/public_profile_location_test.dart`
- `swiftserve-backend/src/services/publicProfileLocation.js`
- `swiftserve-backend/test/publicProfileLocation.test.js`
- `swiftserve-backend/docs/profile-location-privacy.md` (this report)

## Actual local validation — October 30, 2026

Tests ran in new temporary source snapshots, leaving original generated build
outputs and existing safety backups alone. No production credentials or records
were used by the fake-database/emulator tests. Node 22 and the existing installed
Flutter toolchain/dependencies were used; no packages were added or upgraded.

| Check | Actual result |
| --- | --- |
| Five new writer regressions against the original backend controller | All five failed as expected |
| Three new search/discovery privacy regressions against original implementations | All three failed as expected |
| Complete backend `node --test` | 147 passed |
| Final focused Flutter command below | 71 passed |
| Final `flutter analyze --no-pub` | No issues |
| Dedicated demo Firestore privacy suite | 3 passed, including the legacy-exposure characterization |
| Full Flutter suite before the final card-only fix | 419 passed, 2 failed |

The final focused command includes the existing card layout/navigation tests:

```powershell
flutter test --no-pub test/public_profile_location_test.dart test/public_profile_search_test.dart test/registration_address_fields_test.dart test/worker_discovery_test.dart test/profile_identity_test.dart test/nearby_workers_section_test.dart
```

The broad run exposed one introduced issue: combining the locality and distance
text broke the existing exact Nearby label. The final implementation uses separate
text widgets, preserves that label, and passes the existing card assertions plus
three new rendered privacy cases. The 71 focused tests and analyzer were rerun
after this fix; the full suite was not rerun after this card-only change.

The other broad failure is the previously known
`post_request_schedule_test.dart` future-month/day-number issue; that test and
its implementation were not edited here. The previously documented three
review/public-profile rules failures were not rerun or fixed by this task.
The emulator privacy tests are a focused check, not a full security-rules audit
or a claim that existing live public documents have been cleaned.

Manual device tests still needed: both profile roles, both search screens,
city-only/unknown legacy locations, saved-area vs GPS recommendations, editing
the owner's private address, and existing profile/chat navigation after reload.
Privacy of live stored data remains blocked on the approved cleanup/policy steps
above. No production rollout or physical-device verification is claimed.
