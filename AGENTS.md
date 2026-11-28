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
| Student | An applicant: the student portal (Home, Apply, Notifications, Profile). Home (`/home`) is the welcome page a student opens on after signing in: greeting, the four steps, where their application stands, and a button to Apply. |

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
  Firebase Cloud Messaging, and the same notifications by email through
  Gmail's SMTP server, run by `pg_cron`), and `backup-status` (the Admin's
  Backups page: lists, downloads and deletes the weekly encrypted backups
  that a GitHub Actions workflow keeps in a private repository; the GitHub
  token is a Supabase secret and never reaches the browser).
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
3. The **student** (portal page "Apply") fills one form: their **Student
   ID** (no longer asked at registration; locked to the profile's when it
   has a valid one) with a **photo of their school ID** (document
   "School ID", Head-only like the other files; the web app reads the ID
   off the photo, the Android app has no reader so the student types it,
   and the Head's "Student ID checked" step covers both), the official
   **Application Form** (`ApplicationFormData`, `ApplicationFormDialog`,
   auto-filled into `assets/templates/application_form_template.docx` via
   `ApplicationFormDocumentService` and uploaded alongside the application
   so both the Head and the applicant / Student Assistant can preview and
   download it), skills (from the Head's list or typed; typed ones take
   the Head's spelling) and one file per requirement. The Apply card
   and form also remind applicants to bring physical copies of any
   requirements mentioned in the announcement and that shortlisted
   applicants will be interviewed. One application per student per year,
   id `app_<uid>_<academicYear>` (`Application.idFor`); the rules enforce
   the id, the year in effect and an open hiring call. The Apply card also
   lists the offices with an open approved request, with the skills each
   needs (`officesNeedingAssistants`, information only: office name and
   skills, never the supervisor or the request text); the Head still
   decides the placement.
4. The **Head's Applications & Screening page** (`ApplicantScreeningScreen`
   with `ApplicationsPanel`) matches each applicant's skills against the
   open approved requests (`skillMatchesFor`, `SkillMatch`). A low or zero
   match only filters and sorts; nobody is dropped. The Head ticks who goes
   to screening (`sendToScreening`) or **rejects** an application with a
   reason (a wrong document, say); the student can then **apply again**,
   replacing it (the rules allow that update only from `Rejected`).
   Nobody goes to screening or is approved before the Head presses
   **"Student ID checked"** (`markStudentIdChecked`; `updateApplicationStatus`
   refuses otherwise). Approval writes the ID to the profile, verified and
   reserved in `studentIds`, in one transaction (`verifyStudentId`).
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
- Each office has its own code per session (`attendanceQr/{officeId}`,
  made by `AppState.generateAttendanceQrToken(office)`; only the office's
  supervisors, listed by id in `headIds`, may read or write it). The code
  stays the same all session so it can be printed. The function accepts a
  scan only if the code was saved for an active office whose
  `assistantIds` hold the student, and saves that `officeId` on the
  clock-in record. `meta/current_qr`, the old school-wide code, is no
  longer used.
- When there was no code to scan, a Supervisor (their offices' SAs) or the
  Head (any SA) records a finished stretch by hand
  (`AppState.recordManualAttendance`, `lib/widgets/record_attendance_dialog.dart`):
  time-in and time-out both, one session, up to 7 days back, no overlap
  with the SA's other records (pay approval is the Admin's data, so it
  isn't checked). Ids are
  `<uid>_<yyyyMMdd>_manual_<ms>` so they never clash with the function's
  numbered ids.
- Offline: `web/sais-sw.js` caches the app shell, CanvasKit, Firebase's
  scripts and the vendored ZXing (never data); `web/flutter_bootstrap.js`
  must not pass serviceWorkerSettings. `AppState.isOffline` (from
  `lib/services/connectivity.dart`) drives `OfflineBanner`; a session whose
  profile couldn't be reached sets `sessionRestoreFailed` instead of
  inventing a Student; the Head's writing start-up jobs skip while offline.
  Keep `FIREBASE_JS_VERSION` in step with firebase_core_web (a test checks).
- Offices list people by parallel id/name lists; a place with a name but a
  blank id is "unlinked" (`AppState.unlinkedOfficePeople`): the rules and
  the function go by id, so the Head's Offices page warns and offers Link.
- Supervisors and Student Assistants use `AttendanceScreen` (QR
  generate/scan). The Head gets `HeadAttendanceScreen`: a summary of every
  Student Assistant (`AppState.assistantAttendance`) with filters, no QR.
- Hours count only for records timed out, not archived and not missed
  (`AttendanceRecord.countsTowardHours`).
- Staff changes to a record (manual time-out, archive, restore, delete) go
  through `AppState.setManualTimeOut` / `setAttendanceArchived` /
  `deleteAttendance`: they save `editedBy`/`editedAt`/`editNote`, tell the
  student, and put back only their own record if the save fails. Rebuild
  records with `copyWith` so the edit fields aren't dropped. A manual
  time-out must pass `AppState.manualTimeOutProblem` (after the time-in,
  not past the record's session end, not later than now on today's
  record); screens call it before the confirm and show the reason.
- Records are matched to a person by id, and by name only when the record
  was saved without one (`AppState._isRecordOf`): two students may share a
  name. Supervisors' lists use `_supervisedRecordTest` (students the office
  lists by name alone count by their roster ids).
- Sent to Head: a forward must name one of the Supervisor's own students
  (the rules refuse an empty `studentId`; `_forwardStudentId` resolves one
  or throws `SendToHeadProblem` before uploading). Reports and evaluations
  write the forward first under a fixed id (`report_<id>`/`evaluation_<id>`,
  `FirestoreService.addHeadForwardOnce`), then mark the item sent.
- Notifications from Students/Student Assistants are limited by the rules
  to what the app raises (application → Heads, schedule → Heads from an
  SA, report from an SA, task → staff) and every notification must carry
  `createdAt` = server time. Mention notifications
  (`mention_<announcementId>_<uid>`) open the announcement
  (`AppState.announcementMentionedIn`).
- "Today" and the week for hours are Philippine time (`philippineToday`,
  `philippineClock`), never the machine's: tests must not use
  `DateTime.now()` for a date the app stamps (CI runs in UTC).
  `philippineClock` returns a plain local DateTime holding Philippine
  wall-clock fields, to compare with the local DateTimes built from records'
  dates and times; never make it UTC (it was, and every comparison ran 8 h
  off on phones set to Philippine time).

### Payroll

The Head checks each Student Assistant's payroll requirements
(`payrollChecks/{id}`); the Admin can approve a term's payroll only when
everyone in it is Ready. A Student Assistant reads only their own
`payrollChecks` document and own `payrollRecords` (live listeners in
`_startLiveData`); `AppState.myPay` feeds the dashboard's My Pay card.
The same dashboard's My Office card shows the office(s) the Student
Assistant is placed in (`currentUserOffices`) and the supervisors' names, or
that they are not placed yet; it stays hidden until the offices have loaded.
Its "View details" opens the My Office page (`MyOfficeScreen`, `/my-office`, Student
Assistant only): About, Location (with an optional picture), supervisors and
the skills the office looks for. The Head enters About, Location and the
picture in the Offices dialog (`Office.about`, `location`, `locationImagePath`).
The picture is stored under the `announcements/<uid>/` storage root so the
upload function needs no change (it has no delete, so a replaced picture stays
in the bucket).
Each supervisor shows with a picture (initials until they have one). A Student
Assistant can't read `users/{uid}`, so the picture comes from
`supervisorCards/{account id}` = {name, avatar, updatedAt} (`SupervisorCard`):
every staff/Admin session's Users listener calls `AppState.syncSupervisorCards`
(Head/Admin bring every Supervisor's card up to date, a Supervisor only their
own; only what differs is written), and My Office reads them with
`loadSupervisorCards`. Readable by anyone signed in, never carries email or
phone (rules). Needs the rules deployed, or pictures stay as initials.

### Backups (Admin)

The weekly encrypted backup is made outside this repo. The Admin's Backups
page (`lib/screens/backups/`, tab `backups`, `/backups`) shows it through
`BackupService` -> the `backup-status` function (Verify JWT off; it checks the
Firebase token itself and lets only an active Admin through). Download opens a
short-lived GitHub link; Delete never removes the newest backup from a
successful run. `AppState.checkBackupHealth` runs at an Admin's sign-in and
feeds `BackupHealthBanner` (`backupHealth()` in `lib/models/backup_info.dart`).
Admins have no notification bell, push or email, so the warning is a banner,
not a notification document. Restoring is deliberately not in the app (it
needs the backup passphrase and a full-access key).

### Staff sign-up (approved by a Head)

The Register page has a Student | Staff switch. A staff sign-up (Supervisor or
Head) is saved as a **Student** profile with status `Pending` and
`requestedRole`; it cannot sign in (`AppState.blocksSignIn`) and the rules
(`signedIn()`) give it no access until a Head approves it on **Staff Requests**
(`lib/screens/accounts/staff_requests_screen.dart`, `AppState.approveStaffRequest`
/ `declineStaffRequest`): approving sets the role and Active and clears
`requestedRole`, declining sets `Declined`. The rules let a Head change only those
fields, and only on a Pending request. Admin accounts are never self-registered.
Admin, Head and Supervisor profiles do not show Student ID, SA ID, program or
year level.

### Programs (Admin)

The Add Program dialog adds one program or several at once under one
department (rows plus a paste box: `lib/models/program_batch.dart` holds the row
checks and the pasted-list parser). `AppState.saveProgramsBatch` saves them with
one atomic write (`FirestoreService.saveProgramsBatch`), at most 50, and nothing
is saved if any row is wrong. Code uniqueness is checked in the app only, as
for one program; the rules do not enforce it.

### Exports

Six lists (Accounts, Applications, Head Attendance, Students, Rehiring,
Admin Payroll) have one `ExportListButton` menu: **Print** and **Save as
spreadsheet (CSV)**. Each page builds its rows once (`accountsCsvRows`,
`applicationsCsvRows`, `attendanceCsvRows`, `studentsCsvRows`,
`rehiringCsvRows`, `payrollCsvRows`) for both, so paper and file match.
CSV: `lib/utils/csv.dart` (BOM, quoting, formula guard), saved by `saveCsv`.
Print: `lib/utils/list_print.dart` (`PrintableList`, `printableTable`:
cells as text, a column the title already says is dropped) and
`WebPrintUtils.printTable` (a hidden sheet shown only under `@media print`,
landscape, header row repeated; text goes in as DOM text, never HTML).
Not on the Android app.

### Acceptance date

- A profile keeps `acceptedAt`: when the person was accepted as a Student
  Assistant (ISO time, UTC). `changeUserRole` writes it in the same save as
  the role whenever a Student becomes a Student Assistant (the Head's
  approval, Approve Anyway, the Admin's role menu); being accepted again
  later replaces it.
- Accounts from before it was kept have none and show "Not recorded". The
  Head sets or corrects it on the Students page (`_AcceptedDateTile`,
  `AppState.setAcceptedDate`): a picked day is saved as noon Philippine
  time (`lib/utils/philippine_dates.dart`) so it reads as the same day
  anywhere. No future dates.
- Shown on the Students detail dialog and its CSV, the Student Assistant's
  own Profile ("Student Assistant since"), the Approved card on
  Applications, and the Admin's account details.
- Rules: nobody sets or changes their own; a self-made profile can't carry
  one. The Head and Admin branches allow the write.

### Privacy and sign-in

- Registration requires accepting the Privacy Notice
  (`lib/screens/privacy/privacy_notice.dart`, a DRAFT for the school's Data
  Protection Officer); the profile keeps `consentAt`/`consentVersion`, which
  the rules make final. `docs/privacy-data-inventory.md` lists where
  personal data lives and how to erase one person by hand.
- New uploads get random storage names (`randomObjectName`). Pushes for
  pay, ratings, decisions and requirements say only "You have a new
  update" (`pushTextFor` in `clockout-reminders`).
- **Email notifications** (for people who aren't signed in): every
  notification the app saves, and each clock-out reminder, is also emailed by
  `clockout-reminders` to the account's verified Auth address, unless the
  person turned it off (`User.emailNotifications`, `EmailNotificationsCard`;
  only the owner may change it, in the rules). An email NEVER carries a
  notification's own text (staff can write any text for anyone): it says only
  what kind of update it is (`emailFor`) and links to SAIS; the clock-out
  reminder's sentence is built by the function from attendance data. Each
  notification's email has its own claim (`emailClaimedAt` lease,
  `emailedAt`), separate from `pushedAt`. Daily limits live in
  `emailQuota/*` (no rule matches it, so only the function writes it). Needs
  the secrets `EMAIL_FROM_ADDRESS` and `EMAIL_APP_PASSWORD` (a Gmail App
  Password) in Supabase; never put either in the repo. Supabase blocks
  outgoing ports 25 and 587, so SMTP is over TLS on 465.
- "Remember me" picks the Firebase persistence (unchecked: the tab only);
  `IdleSignOutGuard` signs out after 30 minutes idle. Passwords need 10+
  characters and not a common one.
- Account, role and office changes save first (field-level updates and
  transactions: `allocateSaId`, `updateOffices`); a failure is reported to
  the person, not swallowed.

### Tasks, categories, templates and ongoing duties

- A Supervisor assigns tasks (`AssignTaskSheet`); a Student Assistant marks
  one Completed, which sends it for the Supervisor's approval; only approved
  tasks reach the DTR/Accomplishment Report.
- The Head manages the categories (`meta/task_categories`) and the
  templates under them (`meta/task_templates`, `TaskTemplate`) in
  `ManageCategoriesDialog`. Renaming a category renames its tasks and
  templates in one transaction; a category in use can't be deleted. Only the
  Head writes both documents (rules). An opened category also lists the tasks
  given under it ("TASKS GIVEN", `AppState.taskTitleGroups`: by title, with a
  count); the Head can tick several and "Make N templates" in one save
  (`AppState.saveTaskTemplatesFromTasks`, one `upsertTaskTemplates`
  transaction; titles that already are templates and duty logs are skipped).
- The Assign Task form has one "START FROM A SAVED TASK" dropdown: "Type my
  own", the Head's templates, then "Given before": the tasks already given in
  the chosen category that this Supervisor (Head: all) can see, one per
  title, most repeated first, at most 30 (`AppState.recentTaskPicks`,
  in-memory `TaskTemplate`s with ids `recent:<taskId>`), so the same task
  isn't typed over and over.
- DTR/Accomplishment Report: a red weekend/holiday row (a task approved on
  a non-working day, no clock-in) has a "Fix" button that puts the note back
  to "Sunday"/"Saturday"/"Holiday" and clears the red (`_fixDay`; kept when
  the days are rebuilt, `_fixedDays`). A missed time-out is never fixable
  that way. My Office: a supervisor's picture opens larger with "View
  picture" (`showPictureViewer` in `shared_widgets.dart`).
- Phone text: `tool/mobile_audit/` draws every page, role and main dialog at
  360/390 px and 1.3x font with Roboto (what phones draw for 'Inter') and
  reports cut text and overflows (see its README). Widget tests use the
  square test font, so only this, or a test using `test/support/
  real_fonts.dart` (as `test/mobile_text_fit_test.dart` does), can prove a
  text fits. On phones: names/offices take 2-4 lines rather than an
  ellipsis, the phone header puts the year under the page name, and side
  buttons move under the text.
- Branding: `SaisLogo` (`assets/images/sais_logo.png`, the university's maroon
  and gold badge with the system's name) is the app's own logo: sidebar,
  drawer, sign-in/landing header and the launcher/web icons. `AppLogo` (the
  university seal, `logo.jpg`) stays on printed forms (DTR report, payroll
  sheet, screening) and the landing credit line.
- Android: a test APK builds from this code (README, "Android app (APK)"):
  `firebase_auth` must be 6.7+ for Android, always pass `-t lib/main.dart`,
  debug-signed with the default `com.example.projectsais` id; Google
  sign-in and push are web-only so far. Keep features working on the web
  first; Android uses the same services.
- Phones draw pages under the status bar (Android 15 edge-to-edge): both
  shells' top bars add `MediaQuery.viewPaddingOf(context).top` (0 on web and
  desktop).
- An **ongoing duty** (`taskDuties/{id}`, `TaskDuty`) has no due date. On a
  day a Student Assistant has clocked in they log it
  (`AppState.logDutyWork`), which makes one task per duty per day with the
  id `dutylog_<dutyId>_<yyyymmdd>` (`Task.dutyId`, `attendanceId`,
  `workDate`), already waiting for approval. The rules (`isDutyLog` in
  `firestore.rules`) check the duty, the academic year, Philippine today and
  that attendance record. A day with no clock-in makes nothing, so nothing is
  overdue. Duty logs are left out of the DTR's schedule fallback.

### Class schedules (read from the file, approved by the Head)

Every application includes the student's **class schedule**: a JPG, PNG or
PDF of MarSU's schedule grid, stored under `schedules/<uid>/<ms>/<random>`
(Supabase `upload-document`: owner uploads; Head and Supervisors read). The
classes are **read on the student's device** by `web/schedule-reader/`
(Tesseract OCR for pictures and scanned PDFs, pdf.js text for real PDFs,
loaded from jsDelivr on first use with pinned versions and hashes; layout
logic in `sais-schedule-layout.js`, unit tests and a headless-Chrome check
in `tool/schedule_reader_check/`). The student checks and fixes the rows in
`ClassScheduleEditor` (rows marked "Check" are doubtful; units are typed)
before sending. Student uploads are read-only (scanned rows only) where a
reader exists (`ClassScheduleEditor.canScan`); without one (the Android
app) the rows are typed and the Head checks them against the file.

- Saved on the application as `classSchedule {fileName, filePath,
  subjects}` (`ClassScheduleSubmission`); the file is also listed among its
  documents as "Class schedule".
- **Approving the application** adds it as the student's first approved
  version (`_adoptApplicationSchedule`, once per application).
- Approved versions live in `recurringSchedules/{uid}.classSchedules`
  (`ClassScheduleVersion`: `effectiveFrom` day, subjects, file). Only a Head
  writes that field (rules); Student Assistants and Supervisors still save
  the weekly `rules` beside it (merge writes). The version in effect on a
  day is the newest started by then in that academic year
  (`ClassScheduleVersion.inEffect`). Once any version exists, subjects typed
  into `rules` the old way no longer count (`OwnerSchedule.mergedRules`).
- The **Calendar** draws the classes from the version in effect each day
  (`ScheduleService`, `ScheduleEvent.computed`, ids `class_...`; nothing is
  stored per day) and shows `ClassScheduleCard`. "Add Subject" is gone from
  a Student Assistant's calendar.
- A Student Assistant sends a **new schedule** from the card ("Upload new
  schedule", with a start day): `scheduleRequests/{uid}_{ms}` Pending; an
  older waiting one is cancelled; they may withdraw it. The **Head** decides
  on the **Schedule Requests** page (`/schedule-requests`): Approve (one
  transaction adds the version and decides the request, then the old typed
  subjects' calendar days are deleted) or Reject with a reason. The Head can
  also "Edit classes" on a student's calendar (a new version from the day
  picked, same file). Notification type `schedule`.
- The **DTR** Class Schedule table syncs from the version in effect at the
  end of the report's month (or today), so older months keep their
  classes; time in/out defaults come only from work rules, never classes.

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
  width. A list shows `LoadingState` until `AppState.isLoaded('<label>')`
  (its live query has answered once) and only then `EmptyState`, so "nothing
  here" never flashes. A live query that fails goes through
  `AppState._markFailed(label, error)` (never a bare `debugPrint`): the shells
  then show `LoadProblemBanner` with Try again (`retryLoading`), and payroll
  approve/release refuse until `payrollDataLoaded`. A fallback query the
  rules always refuse belongs in `_optionalLoads`. Grey text uses `slate500` or darker (`slate400` is
  for icons and borders: it fails contrast as text). Tappable areas that
  aren't buttons use `TapTarget` (keyboard and screen-reader friendly), and
  icon-only buttons get a `tooltip`. A dropdown with `isExpanded: true` in
  a header toolbar needs a bounded width (`maxWidth`). When a `ButtonStyle` sets `textStyle`, include
  `fontFamily: 'Inter'` (it replaces the theme's). Don't change a chart type
  the user chose without asking.
- **Waiting buttons:** a button whose action waits (a save, an upload, a
  document being built) shows it: use `AsyncButton` (spinner in the icon
  slot, a `busyLabel`, taps ignored meanwhile; `confirm:` for "are you
  sure?" so the spinner starts after the answer) or `BusyIcon` where a
  screen keeps its own flag. Show a failure to the user (red message, or
  inline inside a dialog), never silently. After an `await`, close only
  your own route (`ModalRoute.of(ctx)?.isCurrent`) and check `mounted`.
  Give list items that hold busy state a `ValueKey`.
- **Landing page** (`lib/screens/landing/`): an advertisement for the Student
  Assistant hiring, built on the campus photos (`assets/images/marsu_*.jpg`) with
  MarSU maroon, warm cream and a serif for headings (`LandingColors`,
  `SourceSerifDisplay`). No bright yellow: the user found it hard on the eyes. The
  start-up loader is plain HTML/CSS in `web/index.html` (deep maroon, seal, cream
  arc; fades out on `flutter-first-frame`). Every "Apply" button calls `onGetStarted` (registration); it
  never says hiring is open (it can't know), invents no pay, hours or eligibility,
  and links the Privacy Notice. Link-preview tags live in `web/index.html`
  (`web/og-image.jpg` is 1200x630).
- **Opening stored files:** show a student's document with `showDocumentPreview`
  (`lib/widgets/document_preview.dart`), not by signing a link and leaving the app:
  pictures, PDFs and `.docx` are shown in place, with Download inside the viewer.
  Word files are drawn in the browser by the vendored `web/docx-preview/` (never send
  them to an outside viewer); change anything there only with the check in
  `tool/docx_viewer_check/` (see its README note in `web/docx-preview/README.md`).
- **Data safety:** save first, then update local state and notify people;
  a failed save must leave nothing half-done or announced.
- **No second copy after a save:** a live query delivers a new document as
  soon as it is written, before the save returns. So after `await`ing a
  save, add the record to its list only if it isn't there
  (`AppState._withAdded`, or a `contains`/`find…` check for plain names),
  and give a new record its id before saving (`_newDocId()`), never an
  empty one for Firestore to fill in. `test/live_duplicates_test.dart` has
  a fake whose saves echo through the live query first. A request to a
  server function gets a time limit (`SupabaseStorageService.requestTimeout`).
  When no button can show the wait (a menu item, a scan, a confirmed
  action), wrap the work in `runWithBusy`.
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
(cd tool/schedule_reader_check && npm test)   # schedule reader layout logic
flutter build web --release     # after adding a plugin, delete .dart_tool/flutter_build first
firebase deploy --only firestore:rules   # the project owner deploys
firebase deploy --only hosting
```

## Documents outside this repository

The capstone documents (SRS, test plan, test cases, use-case
post-conditions, HTTP API reference) are kept outside this repo and
updated separately. When a change makes them out of date, say so.
