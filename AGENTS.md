# AGENTS.md — SAIS (Student Assistant Information System)

A guide for coding agents (Codex, Claude Code) working in this repository.
Read it before changing code, and keep it current when a change makes it
wrong.

## What SAIS is

A Flutter **web** app for Marinduque State University's student assistant
program, live at https://sais-6168b.web.app. It covers hiring (hiring calls,
applications, screening), office placement, attendance by QR code, tasks,
DTR/Accomplishment Reports, rehiring, documents and payroll.

**Roles** (`User.role`):

| Role | Does |
|---|---|
| Admin | Accounts, departments, programs, academic year settings, payroll approval. |
| Head | Head of Student Assistantship (never the Admin): hiring calls, applications and screening, offices, skills, rehiring, student documents, payroll requirements, Sent to Head. Signs as "Head, Student Assistantship". |
| Supervisor | Heads an office: requests student assistants, runs attendance (QR), tasks, DTR/Accomplishment Reports, evaluations. |
| Student Assistant | Clocks in and out, does tasks, submits reports. |
| Student | An applicant: the student portal (Apply, Notifications, Profile). |

## Stack

- **Flutter** (web), state in one `ChangeNotifier`: `AppState`, provided
  with `provider`.
- **Firebase** project `sais-6168b`: Authentication, Cloud Firestore (every
  record), Hosting. **Spark plan only**: no Cloud Functions, nothing that
  needs Blaze.
- **Supabase** (free plan): Storage bucket `Documents` (private; the app
  always signs a fresh link) and Edge Functions in `supabase/functions/`:
  `clock-attendance` (QR clock-in/out, decided on the server's clock in
  Philippine time), `upload-document`, `clockout-reminders` (push through
  Firebase Cloud Messaging, run by `pg_cron`).
- **Security** lives in `firestore.rules`: every role's access is enforced
  on the server. A new write path needs a rules change, and a case in
  `test_rules/firestore.rules.test.mjs` (run with `npm test` there; it starts
  the Firestore emulator) before it ships. Anything the app checks that a
  signed-in user could skip by calling Firestore or a function directly
  belongs on the server too.

## Where things are

| Path | What |
|---|---|
| `lib/models/app_state.dart` | Nearly all app logic: loading, live listeners, every action, derived lists. |
| `lib/models/models.dart` | Data classes (`User`, `Office`, `Announcement`, `Application`, `ScreeningRecord`, `AttendanceRecord`, `SkillMatch`, …). |
| `lib/models/assistant_attendance.dart`, `payroll_requirements.dart`, `person_name.dart`, `task_template.dart`, `task_duty.dart` | Smaller models. |
| `lib/services/firestore_service.dart` | Every Firestore read and write. Tests fake it by subclassing. |
| `lib/services/*_document_service.dart` | Word (.docx) generation from templates. |
| `lib/screens/app_shell.dart` | Staff shell: sidebar items per role (`_navItems`, `roles:`), `_buildBody` maps tab ids to screens. |
| `lib/screens/student_portal/` | The Student role's portal. |
| `lib/navigation/app_router.dart` | Web addresses: a page's address is its sidebar label slugged (`Sent to Head` → `/sent-to-head`). |
| `lib/screens/**` | Screens by area (`accounts/` holds most of the Head's pages). |
| `lib/widgets/` | Shared widgets (`HeroBanner`, `UserAvatar`, `showConfirmDialog`, …). |
| `lib/theme/app_theme.dart` | Colours (`AppTheme.maroon`, slate scale) and text theme (font family `Inter`). |
| `test/` | Unit and widget tests (`flutter test`). |
| `firestore.rules`, `storage.rules` | Server-side access rules (Firebase Storage is unused: its rules deny everything). |
| `test_rules/` | Rules tests: `cd test_rules && npm install && npm test` (needs Java for the emulator). |
| `supabase/functions/*/*.test.ts` | Tests of each function's pure rules: `node --test <file>.test.ts` (Node 23.6+), run from the function's folder. |

## How the main flows work

### Hiring a Student Assistant

Students apply **to be a Student Assistant**, never to an office.

1. A **Supervisor** requests a student assistant (office, how many, needed
   skills). It ends with the **Head approving** it, which creates or
   updates the office (`officePlanFor`, `approveAnnouncement`). Students
   never see requests and aren't notified of them.
2. The **Head posts a hiring call** (Post Announcement → "Hiring call":
   documents to upload and the last day to apply; no office, no slots).
   Students apply through the newest approved one this academic year
   (`AppState.currentHiringCall`); closing it closes applications. A
   "Notice" is information only.
3. The **student** (portal page "Apply") fills one form: skills (from the
   Head's list or typed; typed ones take the Head's spelling) and one file
   per requirement. One application per student per year, id
   `app_<uid>_<academicYear>` (`Application.idFor`); the rules enforce the
   id, the year in effect and an open hiring call.
4. The **Head's Applications & Screening page** (`ApplicantScreeningScreen`
   with `ApplicationsPanel`) matches each applicant's skills against the
   open approved requests (`skillMatchesFor`, `SkillMatch`). A low or zero
   match only filters and sorts; nobody is dropped. The Head ticks who goes
   to screening (`sendToScreening`) or **rejects** an application with a
   reason (a wrong document, say); the student can then **apply again**,
   replacing it (the rules allow that update only from `Rejected`).
5. The **interview and assessment form** decides it: Highly Recommended or
   Recommended → `Approved`; With Reservations or Not Recommended →
   `Waitlisted` (the Head can still "Approve Anyway"). Approved makes them
   a Student Assistant with an SA ID and **no office**; the Head places
   them from Offices (sorted by skill match, never blocked by it). The
   Contract of Appointment and Endorsement Letter name the office, so
   they're generated after placement.

Statuses: `Pending` → `For Screening` → `Approved` / `Waitlisted`, or
`Rejected` before screening. `Accepted` is an older spelling of approved.

### Attendance

- Clock-in/out is by QR and decided by the `clock-attendance` function.
  Dates are saved as `Oct 5, 2026`; times as `8:02 AM`.
- Supervisors and Student Assistants use `AttendanceScreen` (QR
  generate/scan). The Head gets `HeadAttendanceScreen`: a summary of every
  Student Assistant (`AppState.assistantAttendance`) with filters, no QR.
- Hours count only for records timed out, not archived and not missed
  (`AttendanceRecord.countsTowardHours`).

### Payroll

The Head checks each Student Assistant's payroll requirements
(`payrollChecks/{id}`); the Admin can approve a term's payroll only when
everyone in it is Ready.

### Tasks, categories, templates and ongoing duties

- A Supervisor assigns tasks (`AssignTaskSheet`); a Student Assistant marks
  one Completed, which sends it for the Supervisor's approval; only approved
  tasks reach the DTR/Accomplishment Report.
- The Head manages the categories (`meta/task_categories`) and the
  templates under them (`meta/task_templates`, `TaskTemplate`) in
  `ManageCategoriesDialog`. Renaming a category renames its tasks and
  templates in one transaction; a category in use can't be deleted. Only the
  Head writes both documents (rules).
- An **ongoing duty** (`taskDuties/{id}`, `TaskDuty`) has no due date. On a
  day a Student Assistant has clocked in they log it
  (`AppState.logDutyWork`), which makes one task per duty per day with the
  id `dutylog_<dutyId>_<yyyymmdd>` (`Task.dutyId`, `attendanceId`,
  `workDate`), already waiting for approval. The rules (`isDutyLog` in
  `firestore.rules`) check the duty, the academic year, Philippine today and
  that attendance record. A day with no clock-in makes nothing, so nothing is
  overdue. Duty logs are left out of the DTR's schedule fallback.

### Skills

Skill documents are keyed by name. Names are unique whatever their case
(`findSkill`, `uniqueSkills`); a Head's session merges duplicates that
differ only in case.

## Conventions

- **Comments** explain why, in plain English, as doc comments (`///`) on
  what isn't obvious. Match the surrounding density. User-facing text is
  plain and specific ("Applications closed on Oct 30, 2026.").
- **Formatting:** run `dart format` only on files you change; much of the
  codebase isn't formatted, and formatting whole files creates noise.
- **Line endings:** Git stores LF; on Windows checkouts some working files
  are CRLF. Keep a file's own style when editing it.
- **Tests:** every change comes with tests in `test/`. `flutter test` must
  pass in full; `flutter analyze` must show no errors or warnings in the
  files you touched. Widget tests that hit the test font's overflow use the
  `FlutterError.onError` filter seen in existing tests.
- **UI:** light, compact headers (`HeroBanner`: title, figures, search),
  maroon only as an accent, no big gradient banners. Check a 390 px phone
  width. When a `ButtonStyle` sets `textStyle`, include
  `fontFamily: 'Inter'` (it replaces the theme's). Don't change a chart type
  the user chose without asking.
- **Data safety:** save first, then update local state and notify people;
  a failed save must leave nothing half-done or announced.
- **Commits:** a short title, grouped bullet points, a `Deploy with:` line
  when rules, hosting or functions must be deployed. Work on
  `feat/landing-page`; `main` is fast-forwarded to it after each push.
- **Never** read, print or commit credentials (service-account JSON,
  keys, `.env` files, secrets). Stay inside this repository.
- **Free plans only:** Firebase Spark, Supabase Free.

## Commands

```sh
flutter pub get
flutter analyze
flutter test
(cd test_rules && npm test)   # after any firestore.rules change
flutter build web --release     # after adding a plugin, delete .dart_tool/flutter_build first
firebase deploy --only firestore:rules   # the project owner deploys
firebase deploy --only hosting
```

## Documents outside this repository

The capstone documents (SRS, test plan, test cases, use-case
post-conditions, HTTP API reference) are kept outside this repo and
updated separately. When a change makes them out of date, say so.
