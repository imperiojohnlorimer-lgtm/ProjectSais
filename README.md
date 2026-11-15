# SAIS: Student Assistant Information System

A web app for Marinduque State University (MarSU) that runs the Student
Assistant program: hiring calls and applications, screening, offices,
attendance by QR code, tasks and reports, payroll, and rehiring. It is built
with Flutter (web) and live at <https://sais-6168b.web.app>; a test Android
app (APK) builds from the same code (see "Android app (APK)" below).

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
(cd supabase/functions/clockout-reminders && node --test reminders.test.ts pushtext.test.ts email.test.ts email-core.test.ts)
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
`FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`, `CLOCKOUT_REMINDER_SECRET`,
and for notification emails `EMAIL_FROM_ADDRESS` and `EMAIL_APP_PASSWORD` (a
Gmail address and its App Password; use a dedicated account, and rotate the
password if it leaks), plus the service-role key Supabase provides to its
functions. The Firebase
web configuration in `lib/firebase_options.dart` and the Supabase publishable
key in `lib/main.dart` are public identifiers by design.

## Android app (APK)

SAIS also builds as an Android app from the same code. It is a **test
build**, shared as an APK file, not a Play Store release:

- **App ID and signing:** the app ID is still Flutter's default
  `com.example.projectsais`, and the release build is signed with the debug
  key. A store release needs a real app ID and its own signing key.
- **Google sign-in and phone notifications:** both are set up for the web
  only. On Android, Google sign-in needs the APK's signing key (SHA-1)
  registered in Firebase, and phone notifications need Firebase Cloud
  Messaging set up for Android. Email/password sign-in, Firestore, file
  uploads and the camera QR scan use the same services as the web.
- **Launcher icon:** the icon is the SAIS logo, in `android/app/src/main/res/`.

To build it:

1. Have the Android SDK and a JDK (17 or newer) installed; `flutter doctor`
   should show the Android toolchain.
2. `firebase_auth` must be 6.7 or newer: 6.5.x does not compile for Android
   against `firebase_core` 4.15 (it expects `customAuthDomain`, which moved).
   Run `flutter pub upgrade firebase_auth` once if `pubspec.lock` holds an
   older one.
3. Build, naming the entry file with a forward slash (on Windows the default
   path reaches the compiler as `lib\\main.dart` and fails with "No 'main'
   method found"):

   ```sh
   flutter build apk --release --split-per-abi -t lib/main.dart
   ```

   The first build downloads about 600 MB of Android libraries and takes
   20 minutes or more; later ones take about 5 to 6 minutes.

The APKs land in `build/app/outputs/flutter-apk/`:
`app-arm64-v8a-release.apk` (about 35 MB) is the one for almost every phone
from the last eight years, `app-armeabi-v7a-release.apk` is for old 32-bit
phones and `app-x86_64-release.apk` for emulators. Install it by opening the
file on the phone and allowing installs from that source; if Android refuses
to install over an older copy, uninstall that first.

On Windows with Developer Mode off, Flutter can't create plugin symlinks after
a package upgrade ("Building with plugins requires symlink support"); turn
Developer Mode on, or build from a copy without the `windows/`, `linux/`,
`macos/` and `ios/` folders.

The app draws under the phone's status bar (Android 15 and later), so both
shells pad their top bar by the status bar height. Phones draw Roboto for the
app's 'Inter' (it isn't bundled); `tool/mobile_audit/` checks every page at
phone width with Roboto for cut-off text.

## Other folders

- `test_rules/`: the Firestore rules tests.
- `tool/mobile_audit/`: finds text cut off on phones (see its README).
- `docs/old/`: earlier design notes, kept for history.
- `AGENTS.md`: the guide for coding agents, and a good map for people too.
