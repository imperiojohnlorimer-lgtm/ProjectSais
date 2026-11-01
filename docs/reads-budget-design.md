# Keeping SAIS inside Firestore's free read quota: a design

**Status: proposal. Nothing here is built.** For the project owner to approve
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

**1. A one-time full load at every sign-in** (`_loadAllFromFirestore`, also run
on a role change and on startup): users, academic settings and archives,
offices, departments, programs, skills, screening records, students,
attendance, class schedules, tasks, reports, evaluations, applications and
documents; for the Head also rehire records, and for Head and Supervisor the
forwards to the Head. Students and Student Assistants' live listeners are
filtered to their own records (by account id), but the one-time load still asks
every role for several whole collections (users, students, evaluations,
applications, documents). The rules refuse most of those for them, and a
refused query is still billed as one read, so it is wasted work rather than a
leak.

**2. Live listeners that read the same collections again** (the first snapshot
of each listener returns every document, then each later change is one read per
listener). Staff listeners: announcements, attendance, tasks, applications,
head forwards, users, students, reports, evaluations, documents, class
schedules, task duties, notifications, offices, departments, programs, skills;
Head also payroll checks, rehire and screening records; Admin also payroll
records and sheets.

So a staff sign-in pays for the same documents **at least twice** (the load and
the listener's first snapshot), and every later change to any of them is billed
again to every open staff session.

## What it costs (estimates, to be measured)

Only one real figure exists: the first weekly backup (2026-09-29) found **511
documents in total** across Firestore. That is small, so today's cost is small.
The risk is growth:

- Per sign-in of a staff account: about `2 x (documents they can read)`.
  At 511 documents that is roughly 1,000 reads; at 5,000 documents, 10,000
  (one Head sign-in would spend a fifth of the day's quota).
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

**Step 0: stop reading everything twice.** The listeners already deliver the
same documents, so the one-time load is largely redundant. Replace it with
"wait for the listeners' first answers" (the app already tracks that with
`isLoaded`). This roughly halves a staff sign-in with no change to what anyone
sees. Risk: low; some derived state (rehire decisions that take effect, archive
checks) is computed from the load and must be re-run when the listeners answer.

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
  period). Records lacking `dateKey` are read by a fallback until the backfill
  is verified complete.
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

## Not covered

Cutting reads is separate from the cron and push functions' own small reads,
from the weekly backup (it reads every document once a week, on GitHub's side,
using the same quota), and from moving to a paid plan, which the project has
ruled out.
