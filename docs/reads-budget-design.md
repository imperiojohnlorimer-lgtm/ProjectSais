# Keeping SAIS inside Firestore's free read quota: a design

**Status: proposal. Step 0 is built (2026-11-02):** every role but the Head reads at sign-in only the academic year settings and the archive list (the Admin also the accounts), and the live queries deliver the rest; the pages wait for the first answers (`AppState.initialDataReady`). The Head still reads what its start-up jobs work from (accounts, students, offices, departments, skills, rehire decisions, applications) - those jobs rewrite roles and archives and must not run on partial live data - but no longer reads attendance, tasks, reports, evaluations, documents and the other big lists a second time. Running the Head's jobs from the live answers is deferred (needs server-confirmed snapshots and a serialized job runner). **Nothing else here is built.** For the project owner to approve
before any code is written, because payroll and the DTR depend on the full
attendance history and a mistake here shows up as wrong pay, not as a slow page.

## The problem

Firebase's free (Spark) plan allows **50,000 document reads a day** across the
whole project. When it is used up, every Firestore read fails until the quota
resets (the app now says so with a banner and a Try again button, but the lists
are still empty or old until then). A read is billed for every document a query
returns, every time it returns it.

Today the Head, the Supervisors and the Admin load whole collections, without a
date limit, and the app asks for most of them **twice** per sign-in. Their cost
grows with the amount of history, not with how much they actually look at.

## What the code does today

Read from `lib/models/app_state.dart` (`_loadAllFromFirestore`,
`_startRealtimeListeners`, `_startLiveData`). "Collection" means every document
in it, any year.

**(Updated 2026-11-02: item 1 below is now only the Head's, and a much smaller one; see the status line above.)**

**1. A one-time full load at every sign-in** (`_loadAllFromFirestore`, also run
on a role change and on startup): users, academic settings and archives,
offices, departments, programs, skills, screening records, students,
attendance, class schedules, tasks, reports, evaluations, applications and
documents; for the Head also rehire records, and for Head and Supervisor the
forwards to the Head. Students and Student Assistants' live listeners are
filtered to their own records (by account id), but the one-time load still asks
every role for several whole collections (users, students, evaluations,
applications, documents). The rules refuse most of those for them; refused
requests are not free of charge in general (what a rule-dependent query costs
is not a fixed one read), so this is wasted work rather than a leak.

**2. Live listeners that read many of the same collections again** (the first
snapshot of each listener returns every document it matches, then each later
change is one read per listener).
- Head: announcements, attendance, tasks, applications, head forwards, users,
  students, reports, evaluations, documents, class schedules, task duties,
  task categories and templates, notifications (own), offices, departments,
  programs, skills, payroll checks, rehire and screening records.
- Supervisor: the same without applications, payroll checks, rehire and
  screening records (the rules give applications to the Head and the
  applicant only).
- Admin: announcements, attendance, applications (own), users, students,
  reports, payroll checks, payroll records and sheets, notifications (own),
  offices, departments, programs, skills; not tasks, evaluations, documents,
  class schedules or duties.
- Student and Student Assistant: shared announcements, offices, departments,
  programs and skills, plus their own attendance, applications, reports, tasks,
  duties, schedules, pay and notifications.

So for the collections both paths cover, a staff sign-in pays for the same
documents **about twice** (the load and the listener's first snapshot). The
paths do not cover identical sets (announcements, duties and payroll are only
listened to; departments are loaded by two queries), so "twice the readable
documents" is a rough upper figure, not a budget. Every later change is billed
again to every open session that listens to it.

## What it costs (estimates, to be measured)

Only one real figure exists: the first weekly backup (2026-09-29) found **511
documents in total** across Firestore. That is small, so today's cost is small.
The risk is growth:

- Per sign-in of a staff account: up to about `2 x (documents they can
  read)` for the collections both paths cover. At 511 documents that is
  roughly 1,000 reads; at 5,000 documents, 10,000 (one Head sign-in would spend
  a fifth of the day's quota). Billing is not that simple in either direction:
  a listener that reconnects re-bills its query unless the browser cache
  resumes it (and resuming stops working after the connection has been down
  more than about 30 minutes); deleted documents are not billed to listeners;
  results served from a cache are not billed.
- Per day: `sign-ins x that figure` + `changes x open staff sessions` (each
  attendance clock-in or out, task or notification change is re-read by every
  open staff session) + page reloads (each reload is a new sign-in cost) +
  every extra open tab + the Supabase cron and push functions' small reads.
- Attendance and reports are the part that grows without limit: one record per
  assistant per session per day. With 100 assistants clocking twice a day on
  about 120 school days, that is on the order of 24,000 attendance documents a
  year, in a collection every staff sign-in reads in full.

The honest summary: **the app is fine at today's size, and its cost is
proportional to total history.** The quota is reached by years of data, or by
many staff sign-ins and reloads in one day, long before the number of students
looks large.

**To measure before deciding (read-only, needs the owner's approval to run
against production):** a `count()` aggregation per collection (billed at about
one read per 1,000 documents, so cheap), and Firebase console's Usage tab for the
real daily reads. The design below is written so it still holds whatever the
counts turn out to be.

## Options, cheapest and safest first

**Step 0: stop reading everything twice, carefully.** The listeners deliver
most of the same documents, so much of the one-time load is redundant. But the
load is also where start-up *work* happens, and that work must be kept:
rehire decisions are put into effect once the settings, users, students,
offices and the decisions are all ready (and a decision is marked applied even
when its person is missing, so running it early loses it); office assignments
are synchronised; schedule ownership is migrated; approved applications'
skills are imported; archive metadata is loaded, and archive timers skip a
deadline that has already passed, so scheduling alone can't replace running the
check once at start. So Step 0 means: keep that work, but trigger it when the
specific listeners it needs have delivered **server-confirmed** data, then drop
only the duplicate reads. Estimated saving: up to about half of a staff
sign-in. Risk: medium, not low: this is a behaviour-preserving refactor of the
start-up sequence and needs its own tests (one per piece of start-up work).

**Step 1: only load what a role uses.** Several roles read collections they
never display (for example students and assistants reading the whole student
roster and application lists, or Supervisors reading everyone's attendance when
their screens show their own office). Narrow each query to what the role's
screens show, matching what the Firestore rules already allow. Risk: low to
medium; needs a screen-by-screen check.

**Step 2: period-scoped history for attendance, reports and tasks.** Load only
the current academic year (and the month a screen is looking at), and fetch
older periods on demand.
- Needs a sortable field on each record. Attendance stores its date as display
  text (`Oct 26, 2026`), which can't be range-queried. Add `dateKey`
  (`2026-10-26`) to new records and **backfill** old ones with a one-off admin
  script; index it.
- Queries become `where dateKey >= termStart` (and `<= termEnd` for a chosen
  period). A query on a field never returns documents that lack it, so
  unbackfilled records are invisible to it: the fallback must be a separate,
  explicit read (a scan with a manifest of what was keyed), not "treat missing
  as null". The backfill needs semantic date validation (the stored text may be
  malformed), a plan for records written by an older app version while it
  runs, and a reconciliation report listing every record, not only matching
  counts.
- Reports and tasks need the equivalent (`academicYear` already exists on
  several; the rest need a key).

**Step 3: browser cache.** Turn on Firestore's persistent cache so a repeat
visit resumes from what the browser already has. Helps repeat sign-ins on the
same device; it does not remove the first load, and a **shared computer** would
then hold the previous person's data on disk, so this needs a sign-out wipe or
is left off for staff sessions. Measure before relying on it.

## Completeness rules (what must never be wrong)

Cutting what is loaded is only safe if nothing that needs the full picture can
silently run on a partial one. These are the places that do:

- **Payroll.** It finds former assistants through their attendance records, and
  attendance of a year that was archived stays payable. So approving or
  releasing a period must refuse until **that exact period** is fully loaded
  (or fetch it first), however far back it is. Today's guard
  (`payrollDataLoaded`) only knows whether each live query answered, not what
  date range it covered. It must become "loaded range covers the period", tracked
  per query, range and sign-in generation, not per label.
- **DTR / Accomplishment Reports.** Built per month from attendance and the
  approved tasks of that month: a month view must load that month's attendance
  and tasks, not rely on the current term.
- **Head attendance summary, dashboard totals and hour counts.** Anything that
  sums across a period must say which period it covers and load it.
- **Year rollover and Undo.** A period loaded under one academic year must be
  reloaded when the Admin starts the next year or undoes it; archived
  copies, manual archives and live records must not be double counted.
- **A failure never counts as "nothing there".** A range that failed to load is
  reported (the banner) and blocks payroll, as now.
- **"Answered" is not "complete".** `isLoaded` also counts failed answers, and
  neither it nor the payroll guard knows whether a snapshot came from the
  browser's cache or the server (the service's streams drop that detail).
  Anything that unlocks payroll or generates a DTR must wait for
  **server-confirmed** snapshots (Firestore's snapshot metadata) for the exact
  range. Without that, a cached, partial result could unlock work.
- **Payroll's full dependency list**: attendance for the period (including
  year-archived), the identity mappings that tie records to people, reports,
  the Head's checks, existing payouts and the roster of former assistants.
- **DTR's**: attendance, class schedules (with their fallback) and tasks chosen
  by **completion date** for that month. Today the DTR excludes archived
  attendance and tasks while payroll deliberately keeps year-archived
  attendance payable: the design must name one canonical set of records for each
  and de-duplicate archive copies against live ones.
- **Shared lists.** A range loaded for one screen must not overwrite the list
  another screen is using (a Head looking at last year must not change this
  term's totals).

## Rollout order (each step deployable on its own)

1. Measure (counts and the console's usage), agree the targets.
2. Step 0, with tests that the same screens show the same data.
3. Add `dateKey` to writers; deploy the rules and indexes; run the backfill;
   **verify parity** (every record has a key, counts equal the old totals).
4. Switch readers to period queries behind the completeness guard, keeping the
   fallback to full loads for records without a key.
5. Retire the fallback once parity has held for a full term.
6. Re-measure; decide on Step 3.

## Tests the work must come with

- The same figures with and without scoping: payroll for a past period,
  year-archived attendance, a former assistant, DTR for a past month.
- The guard refuses payroll when the period isn't covered, a retry doesn't let
  a stale range pass, and a failed range blocks it.
- Rollover and Undo reload the right periods.
- Rules and indexes for the new queries (the rules emulator suite), and a
  backfill script test on sample data with parity checks.

## Decisions needed from the project owner

1. Approve running the read-only `count()` measurement against production.
2. Is Step 0 (stop the double load) alone enough for now, or should Step 2
   follow? (Step 0 is the cheap one; Step 2 is the one that stops the cost
   growing with history.)
3. Is a "Load earlier periods" button acceptable on the Head's and Admin's
   history views, or must everything always be on screen?
4. Staff on shared computers: is a persistent browser cache acceptable?

## Other readers of the same quota (measure them too)

Other collections stay unbounded after Step 2; archiving a year scans all
attendance; the cron job reads the day's attendance twice a day; push and email
add notification, profile, push-token and email-counter reads on every
notification; the weekly backup reads every document once a week (on GitHub's
side, against the same quota); retries, reconnects and multiple open tabs each
repeat a query. Persistent caching also needs its tab coordination and a
reliable clean-up between people on a shared computer worked out first. Moving
to a paid plan is not an option for this project.
