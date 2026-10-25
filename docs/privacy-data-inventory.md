# Personal data in SAIS: where it is, and how to erase it

For the school's Data Protection Officer. It lists everything SAIS keeps that
can identify a person, read from the Firestore rules and the code, so a request
under the Data Privacy Act (RA 10173) to see, correct or erase someone's data
can be answered. It contains no personal data and no secrets.

**There is no "erase my data" button.** Deleting an account in SAIS only marks
the profile deleted and archived (so the person can't sign in); the rest stays.
Erasing a person is a manual procedure, below. Building it into the system is a
separate piece of work, because it must delete in about 25 places, remove the
sign-in itself, and keep what the school is required to keep.

## Where personal data lives

### Sign-in (Firebase Authentication)
Email address, password (hashed by Google), sign-in providers (password,
Google). Removed only in the Firebase console, under Authentication.

### Cloud Firestore (collections)

| Collection | What it holds about a person | Who can read it |
|---|---|---|
| `users` | Name (and its parts), email, phone, address, photo, skills, Student ID, SA ID, course/program, year level, department, campus, role, status, consent time and version | The person; Head, Supervisor, Admin |
| `studentIds` | Which account holds a Student ID | Any signed-in account (one ID at a time) |
| `students` | Roster record: name, email, department, campus, hours, phone, address, photo | Head, Supervisor, Admin, the person |
| `officeAssignments`, `offices` | Which office a person is in; names of supervisors and assistants | Head, Supervisors, assistants |
| `announcements` | Name of whoever posted; attachments | Everyone signed in |
| `applications` | Applicant name, skills, answers, uploaded requirement documents, screening remarks, decisions | The applicant; Head |
| `screeningRecords` | Interview ratings and remarks about an applicant | Head |
| `attendance` | Clock-in and clock-out times by date, hours | The person; Head, Supervisor, Admin |
| `classSchedules`, `recurringSchedules`, `schedule_events` | Class and duty schedules | The person; Head, Supervisor |
| `tasks`, `taskDuties` | Tasks assigned, completion and review notes | The person; Head, Supervisor |
| `reports` | Accomplishment reports and attachments | The person; Head, Supervisor, Admin |
| `evaluations` | Performance ratings and comments | Head, Supervisor |
| `rehireRecords` | Rehire decisions per term | Head |
| `headForwards` | Items a Supervisor forwarded to the Head (reports, evaluations, DTRs) | Head, the Supervisor who sent it |
| `payrollRecords`, `payrollSheets` | Hours, rates and pay per person and period; the printed sheet with names | Admin; Head reads records |
| `payrollChecks` | The Head's check of each person's payroll requirements | Head, Admin |
| `documents`, `documentFolders` | Files and folders the Head keeps about students | Head |
| `notifications` | Messages to a person, which can mention pay, ratings, decisions | Only the person |
| `pushTokens` | A code that identifies a browser or phone for push notifications | Only the person |
| `meta/heads` | Account ids of the Heads | Everyone signed in |
| `meta/academic_year_archives/years/*` | Copies of each closed year's applications, reports, attendance, tasks, with the people in them | Head, Admin |

### Supabase Storage (private bucket `Documents`)
Files people upload, under `reports/<account id>/`, `applications/<account
id>/` and `announcements/<account id>/`, and the archived copies under
`academic_year_archives/<year>/`. Since October 2026 new files are stored under
random names; older ones keep the person's own file name in the path. Files open
only through links that expire after an hour.

### Elsewhere
- **Backups**: a weekly encrypted copy of every Firestore document and every
  file is kept for 22 days (GitHub Actions artifacts). An erased person's data
  disappears from them as the old copies expire; restoring one must not
  bring an erased person back.
- **Function logs** (Supabase): error messages; no personal text is logged on
  purpose.
- **Push messages** pass through Google's Firebase Cloud Messaging. Since
  October 2026 pay, rating, rehire and payroll-requirement notifications are
  sent without their details.

## What the school must keep
Payroll, attendance and accomplishment records the school needs for its own
accounting and audit. The DPO decides how long (the privacy notice says "as long
as the school must keep them"). When a person is erased these are not deleted:
the name is replaced by "Erased user" and the record keeps only what the
accounting needs.

## Manual procedure to erase one person
1. **Confirm who is asking**, and write down the request and the decision (what
   was erased, what was kept and why).
2. **Firebase console → Authentication**: delete the user (this stops sign-in and
   frees the email).
3. **Firestore** (console or the admin tools), for the person's account id `U`:
   - delete `users/U`, `pushTokens` where `userId == U`, `notifications` where
     `userId == U`, `officeAssignments/U`, `payrollChecks/U`, `students/U` (and
     any students record with their `userId` or email);
   - delete `studentIds/<their Student ID>` if they held one;
   - remove them from `offices` (`assistantIds`/`assistantNames`, `headIds`/
     `headNames`) if the Head's session has not already;
   - delete `applications`, `screeningRecords`, `tasks`, `taskDuties`,
     `classSchedules`, `recurringSchedules` and `schedule_events` for them;
   - for records the school keeps (`attendance`, `reports`, `evaluations`,
     `payrollRecords`, `payrollSheets`, `rehireRecords`, `headForwards`, and the
     yearly archives): replace the name with "Erased user" and delete free-text
     comments and attachments, keeping dates and hours.
4. **Supabase → Storage → Documents**: delete the person's folders under
   `reports/U/`, `applications/U/` and `announcements/U/`, and any archived
   copies under `academic_year_archives/` that name them.
5. **Backups**: note the date; copies up to 22 days old still hold the data and
   expire by themselves. Never restore a backup over live data without
   re-applying erasures made since.
6. **Tell the person** what was done, and what was kept and why.

## Known limits
- Staff roles can read every profile (the app matches people across screens).
- Files uploaded before October 2026 carry the person's own file name in the
  path.
- A Supervisor's access to a person ends when they leave the office, but
  records they made stay with the school.
