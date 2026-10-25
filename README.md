# SAIS: Student Assistant Information System

A web app for Marinduque State University (MarSU) that runs the Student
Assistant program: hiring calls and applications, screening, offices,
attendance by QR code, tasks and reports, payroll, and rehiring. It is built
with Flutter (web) and live at <https://sais-6168b.web.app>.

Roles: **Admin** (accounts, departments, programs, academic year settings,
payroll), **Head** of Student Assistantship, **Supervisor** (heads an
office), **Student Assistant** and **Student** (applicant).

## How it is put together

| Part | What it does |
|---|---|
| Flutter app (`lib/`) | The whole interface and the app's logic (`lib/models/app_state.dart`). |
| Firebase `sais-6168b` (Spark plan) | Authentication, Cloud Firestore (all records), Hosting. Access rules are in `firestore.rules`. |
| Supabase (Free plan) | Private file storage and three Edge Functions in `supabase/functions/`: `clock-attendance`, `upload-document`, `clockout-reminders`. |

Both services stay on their free plans. See `AGENTS.md` for the code map and
the conventions to follow when changing things.

## Running it

You need the Flutter SDK (3.41 or newer, which bundles Dart 3.11).

```sh
flutter pub get
flutter run -d chrome          # development
flutter build web --release    # production build into build/web
```

## Tests

```sh
flutter analyze
flutter test                                   # app tests
(cd test_rules && npm ci && npm test)          # Firestore rules, on the emulator (needs Java)
(cd supabase/functions/clock-attendance && node --test records.test.ts sessions.test.ts)
(cd supabase/functions/upload-document && node --test paths.test.ts)
(cd supabase/functions/clockout-reminders && node --test reminders.test.ts)
```

The function tests need Node 23.6 or newer. The same checks run on every push
(`.github/workflows/ci.yml`).

## Deploying

The project owner deploys. Order matters when a change touches the rules:

1. `firebase deploy --only firestore:rules` (the rules; files live in Supabase Storage, not Firebase Storage, so there is nothing to deploy for it)
2. `flutter build web --release`, then `firebase deploy --only hosting`
3. Supabase functions: paste each `supabase/functions/<name>/index.ts` into
   the function's editor in the Supabase dashboard.

Secrets are set in the Supabase dashboard, never in this repository:
`FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`, `CLOCKOUT_REMINDER_SECRET`
(and the service-role key Supabase provides to its functions). The Firebase
web configuration in `lib/firebase_options.dart` and the Supabase publishable
key in `lib/main.dart` are public identifiers by design.

## Other folders

- `test_rules/`: the Firestore rules tests.
- `docs/old/`: earlier design notes, kept for history.
- `AGENTS.md`: the guide for coding agents, and a good map for people too.
