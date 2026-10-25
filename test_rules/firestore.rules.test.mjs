// Tests firestore.rules against the local Firestore emulator.
//
//   cd test_rules && npm install && npm test
//
// `npm test` starts the emulator, runs this file and stops it again. Each
// test says who is asking and what they may or may not do; the "keeps working"
// tests are the app's own flows, which a tightened rule must not break.
import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc,
  setDoc,
  updateDoc,
  deleteDoc,
  getDoc,
  runTransaction,
  setLogLevel,
} from 'firebase/firestore';

// The emulator reports every refusal the tests expect; keep the output readable.
setLogLevel('silent');

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-sais',
    firestore: {
      rules: readFileSync(
        process.env.RULES_PATH ?? new URL('../firestore.rules', import.meta.url),
        'utf8',
      ),
    },
  });
});

after(async () => {
  await env.cleanup();
});

const accounts = {
  admin: { name: 'Ada Admin', role: 'Admin' },
  head: { name: 'Hana Head', role: 'Head' },
  sup: { name: 'Sam Supervisor', role: 'Supervisor' },
  sup2: { name: 'Sol Supervisor', role: 'Supervisor' },
  sa: { name: 'Sia Assistant', role: 'Student Assistant' },
  stu: { name: 'Stu Student', role: 'Student' },
};

// Fresh data for every test: every account, one office headed by `sup` with
// `sa` in it, the academic year settings, and a Head's open hiring call.
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, a] of Object.entries(accounts)) {
      await setDoc(doc(db, 'users', uid), {
        ...a,
        email: `${uid}@example.com`,
        status: 'Active',
      });
    }
    await setDoc(doc(db, 'offices', 'o1'), {
      isActive: true,
      headIds: ['sup'],
      assistantIds: ['sa'],
    });
    await setDoc(doc(db, 'officeAssignments', 'sa'), { officeId: 'o1' });
    await setDoc(doc(db, 'meta', 'academic_year_settings'), {
      academicYear: '2026-2027',
      allowApplications: true,
    });
    await setDoc(doc(db, 'announcements', 'call1'), {
      title: 'Hiring',
      body: 'Apply',
      postedByRole: 'Head',
      postedById: 'head',
      approvalStatus: 'Approved',
      isOpen: true,
      acceptsApplications: true,
    });
  });
});

const as = (uid) =>
  env
    .authenticatedContext(uid, { email: `${uid}@example.com`, email_verified: true })
    .firestore();

const request = (over = {}) => ({
  title: 'Need two assistants',
  body: 'Library',
  postedBy: 'Sam Supervisor',
  postedByRole: 'Supervisor',
  postedById: 'sup',
  approvalStatus: 'Pending',
  isOpen: false,
  acceptsApplications: false,
  ...over,
});

// ── announcements ──────────────────────────────────────────────────────

test('a Supervisor files a request in their own name, Pending and closed', async () => {
  await assertSucceeds(setDoc(doc(as('sup'), 'announcements', 'r1'), request()));
});

test('a Supervisor cannot post an approved hiring call as the Head', async () => {
  const db = as('sup');
  for (const over of [
    { postedByRole: 'Head' },
    { approvalStatus: 'Approved' },
    { isOpen: true },
    { postedById: 'sup2' },
    { postedById: 'head', postedByRole: 'Head', approvalStatus: 'Approved', isOpen: true },
  ]) {
    await assertFails(setDoc(doc(db, 'announcements', 'x'), request(over)));
  }
});

test('a student, an assistant or the Admin cannot post announcements', async () => {
  for (const uid of ['stu', 'sa', 'admin']) {
    await assertFails(
      setDoc(doc(as(uid), 'announcements', 'x'), request({ postedById: uid })),
    );
  }
});

test('a Supervisor cannot change a Head call or approve their own request', async () => {
  const db = as('sup');
  await assertFails(updateDoc(doc(db, 'announcements', 'call1'), { isOpen: false }));
  await assertFails(deleteDoc(doc(db, 'announcements', 'call1')));

  await assertSucceeds(setDoc(doc(db, 'announcements', 'r1'), request()));
  await assertFails(updateDoc(doc(db, 'announcements', 'r1'), { approvalStatus: 'Approved' }));
  await assertFails(updateDoc(doc(db, 'announcements', 'r1'), { isOpen: true }));
  await assertFails(updateDoc(doc(db, 'announcements', 'r1'), { postedByRole: 'Head' }));
  await assertFails(updateDoc(doc(db, 'announcements', 'r1'), { postedById: 'sup2' }));
});

test('another Supervisor cannot touch someone else\'s request', async () => {
  await assertSucceeds(setDoc(doc(as('sup'), 'announcements', 'r1'), request()));
  await assertFails(updateDoc(doc(as('sup2'), 'announcements', 'r1'), { title: 'Mine now' }));
  await assertFails(deleteDoc(doc(as('sup2'), 'announcements', 'r1')));
});

test('a Supervisor may edit or withdraw their own pending request', async () => {
  const db = as('sup');
  await assertSucceeds(setDoc(doc(db, 'announcements', 'r1'), request()));
  await assertSucceeds(updateDoc(doc(db, 'announcements', 'r1'), { title: 'Three assistants' }));
  await assertSucceeds(deleteDoc(doc(db, 'announcements', 'r1')));
});

test('once decided, a Supervisor cannot edit or delete their request', async () => {
  await assertSucceeds(setDoc(doc(as('sup'), 'announcements', 'r1'), request()));
  await assertSucceeds(
    updateDoc(doc(as('head'), 'announcements', 'r1'), { approvalStatus: 'Approved' }),
  );
  await assertFails(updateDoc(doc(as('sup'), 'announcements', 'r1'), { title: 'Changed' }));
  await assertFails(deleteDoc(doc(as('sup'), 'announcements', 'r1')));
});

test('the Head posts hiring calls and decides requests (keeps working)', async () => {
  const db = as('head');
  // The Head's form leaves postedByRole off, and sets no approvalStatus.
  await assertSucceeds(
    setDoc(doc(db, 'announcements', 'call2'), {
      title: 'Hiring 2',
      body: 'Apply',
      isOpen: true,
      acceptsApplications: true,
    }),
  );
  await assertSucceeds(setDoc(doc(as('sup'), 'announcements', 'r1'), request()));
  await assertSucceeds(
    updateDoc(doc(db, 'announcements', 'r1'), {
      approvalStatus: 'Rejected',
      rejectionReason: 'No budget',
    }),
  );
  await assertSucceeds(updateDoc(doc(db, 'announcements', 'call1'), { isOpen: false }));
  await assertSucceeds(deleteDoc(doc(db, 'announcements', 'call2')));
  // Everyone signed in reads them.
  await assertSucceeds(getDoc(doc(as('stu'), 'announcements', 'call1')));
});

// ── applying (the hiring call a Supervisor can no longer forge) ───────────

const application = (uid, over = {}) => ({
  applicantId: uid,
  applicantName: accounts[uid].name,
  academicYear: '2026-2027',
  announcementId: 'call1',
  status: 'Pending',
  ...over,
});

test('a student applies through the Head\'s open hiring call (keeps working)', async () => {
  await assertSucceeds(
    setDoc(doc(as('stu'), 'applications', 'app_stu_2026-2027'), application('stu')),
  );
});

test('a student cannot apply through a call a Supervisor forged', async () => {
  // The forged call can't be written any more...
  await assertFails(
    setDoc(
      doc(as('sup'), 'announcements', 'forged'),
      request({ postedByRole: 'Head', approvalStatus: 'Approved', isOpen: true, acceptsApplications: true }),
    ),
  );
  // ...so applying to it finds nothing.
  await assertFails(
    setDoc(
      doc(as('stu'), 'applications', 'app_stu_2026-2027'),
      application('stu', { announcementId: 'forged' }),
    ),
  );
});

test('a Supervisor\'s request is not a hiring call', async () => {
  await assertSucceeds(setDoc(doc(as('sup'), 'announcements', 'r1'), request()));
  await assertSucceeds(
    updateDoc(doc(as('head'), 'announcements', 'r1'), {
      approvalStatus: 'Approved',
      isOpen: true,
      acceptsApplications: true,
    }),
  );
  await assertFails(
    setDoc(
      doc(as('stu'), 'applications', 'app_stu_2026-2027'),
      application('stu', { announcementId: 'r1' }),
    ),
  );
});

test('a rejected application can be replaced by its applicant (keeps working)', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(
      doc(ctx.firestore(), 'applications', 'app_stu_2026-2027'),
      application('stu', { status: 'Rejected' }),
    );
  });
  await assertSucceeds(
    setDoc(doc(as('stu'), 'applications', 'app_stu_2026-2027'), application('stu')),
  );
});

// ── attendance ─────────────────────────────────────────────────────────

const record = (over = {}) => ({
  studentId: 'sa',
  studentName: 'Sia Assistant',
  date: 'Oct 26, 2026',
  timeIn: '8:00 AM',
  timeOut: '11:30 AM',
  totalHours: 3.5,
  ...over,
});

test('a Supervisor saves ordinary hours for their own assistant', async () => {
  await assertSucceeds(setDoc(doc(as('sup'), 'attendance', 'a1'), record()));
  await assertSucceeds(
    updateDoc(doc(as('sup'), 'attendance', 'a1'), { totalHours: 4, isInvalid: false }),
  );
});

test('hours must be blank or between 0 and 12', async () => {
  for (const uid of ['sup', 'head']) {
    const db = as(uid);
    await assertSucceeds(setDoc(doc(db, 'attendance', `ok_${uid}`), record({ totalHours: 12 })));
    await assertFails(setDoc(doc(db, 'attendance', `big_${uid}`), record({ totalHours: 40 })));
    await assertFails(setDoc(doc(db, 'attendance', `neg_${uid}`), record({ totalHours: -1 })));
    await assertFails(setDoc(doc(db, 'attendance', `str_${uid}`), record({ totalHours: '4' })));
    await assertFails(
      setDoc(doc(db, 'attendance', `before_${uid}`), record({ hoursBeforeWeeklyCap: 99 })),
    );
  }
});

test('an open record has no hours, and archiving it still works', async () => {
  const db = as('sup');
  const open = record();
  delete open.timeOut;
  delete open.totalHours;
  await assertSucceeds(setDoc(doc(db, 'attendance', 'open1'), open));
  await assertSucceeds(updateDoc(doc(db, 'attendance', 'open1'), { isArchived: true }));
});

test('a manual time-out trimmed by the weekly cap saves both figures', async () => {
  const db = as('sup');
  const open = record();
  delete open.timeOut;
  delete open.totalHours;
  await assertSucceeds(setDoc(doc(db, 'attendance', 'a1'), open));
  await assertSucceeds(
    updateDoc(doc(db, 'attendance', 'a1'), {
      timeOut: '11:30 AM',
      totalHours: 1.5,
      hoursBeforeWeeklyCap: 3.5,
      isInvalid: false,
    }),
  );
});

test('a Supervisor still cannot write attendance for someone else\'s assistant', async () => {
  await assertFails(setDoc(doc(as('sup2'), 'attendance', 'a1'), record()));
  await assertFails(setDoc(doc(as('sa'), 'attendance', 'a1'), record()));
});

// ── meta/heads ─────────────────────────────────────────────────────────

test('the Head and the Admin publish the Head list; a Supervisor cannot', async () => {
  await assertSucceeds(setDoc(doc(as('head'), 'meta', 'heads'), { ids: ['head'] }));
  await assertSucceeds(setDoc(doc(as('admin'), 'meta', 'heads'), { ids: ['head'] }));
  await assertFails(setDoc(doc(as('sup'), 'meta', 'heads'), { ids: ['sup'] }));
  await assertFails(setDoc(doc(as('stu'), 'meta', 'heads'), { ids: ['stu'] }));
});

test('everyone signed in reads the Head list', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'meta', 'heads'), { ids: ['head'] });
  });
  await assertSucceeds(getDoc(doc(as('stu'), 'meta', 'heads')));
});

test('a Supervisor can still write the other meta documents they always could', async () => {
  await assertSucceeds(
    setDoc(doc(as('sup'), 'meta', 'schedule_owners_migrated'), { done: true }),
  );
});

// ── notifications ──────────────────────────────────────────────────────

const note = (userId, over = {}) => ({
  userId,
  title: 'New Application',
  message: 'Someone applied',
  type: 'application',
  isRead: false,
  ...over,
});

test('a student alerts the Head with a short plain note (keeps working)', async () => {
  await assertSucceeds(setDoc(doc(as('stu'), 'notifications', 'n1'), note('head')));
  await assertSucceeds(setDoc(doc(as('stu'), 'notifications', 'n2'), note('stu', { type: 'system' })));
});

test('notification text has a limit, whoever sends it', async () => {
  const longTitle = 'T'.repeat(101);
  const longMessage = 'M'.repeat(501);
  for (const uid of ['stu', 'sup', 'head', 'admin']) {
    await assertFails(
      setDoc(doc(as(uid), 'notifications', `t_${uid}`), note('head', { title: longTitle })),
    );
    await assertFails(
      setDoc(doc(as(uid), 'notifications', `m_${uid}`), note('head', { message: longMessage })),
    );
  }
  // The edge of the limit is allowed.
  await assertSucceeds(
    setDoc(
      doc(as('sup'), 'notifications', 'edge'),
      note('head', { title: 'T'.repeat(100), message: 'M'.repeat(500) }),
    ),
  );
});

test('a student still cannot notify an assistant or attach a link', async () => {
  await assertFails(setDoc(doc(as('stu'), 'notifications', 'n1'), note('sa')));
  await assertFails(
    setDoc(doc(as('stu'), 'notifications', 'n2'), note('head', { attachmentUrl: 'https://evil.example' })),
  );
  await assertFails(setDoc(doc(as('stu'), 'notifications', 'n3'), note('head', { type: 'payroll' })));
});

test('a notification with no text fields is refused only if they are not strings', async () => {
  await assertFails(setDoc(doc(as('sup'), 'notifications', 'n1'), note('sa', { title: 5 })));
  await assertSucceeds(setDoc(doc(as('sup'), 'notifications', 'n2'), note('sa')));
});

test('a notification is private to its recipient', async () => {
  await assertSucceeds(setDoc(doc(as('sup'), 'notifications', 'n1'), note('sa')));
  await assertSucceeds(getDoc(doc(as('sa'), 'notifications', 'n1')));
  await assertFails(getDoc(doc(as('stu'), 'notifications', 'n1')));
});

// ── Student Assistant numbers, field-level account changes, office moves ──

// What FirestoreService.allocateSaId does, with the same reads and writes.
const allocateSaId = (db, userId) =>
  runTransaction(db, async (tx) => {
    const userRef = doc(db, 'users', userId);
    const counterRef = doc(db, 'meta', 'saCounter');
    const user = await tx.get(userRef);
    if ((user.data()?.saId ?? '') !== '') return user.data().saId;
    const counter = await tx.get(counterRef);
    const next = counter.exists() ? counter.data().next : 1;
    tx.set(counterRef, { next: next + 1 });
    tx.update(userRef, { saId: `SA ${String(next).padStart(3, '0')}` });
    return `SA ${String(next).padStart(3, '0')}`;
  });

test('the Head takes the next SA number in a transaction', async () => {
  const db = as('head');
  assert.equal(await assertSucceeds(allocateSaId(db, 'stu')), 'SA 001');
  // Asking again returns the same one; the counter moved on once.
  assert.equal(await assertSucceeds(allocateSaId(db, 'stu')), 'SA 001');
  const counter = await getDoc(doc(db, 'meta', 'saCounter'));
  assert.equal(counter.data().next, 2);
});

test('nobody but the Head touches the SA counter', async () => {
  for (const uid of ['sup', 'admin', 'sa', 'stu']) {
    await assertFails(setDoc(doc(as(uid), 'meta', 'saCounter'), { next: 99 }));
    await assertFails(allocateSaId(as(uid), 'stu'));
  }
  // (Any signed-in user can read meta documents; the number is no secret.)
});

test('the Head changes only the role or status of a Student or assistant', async () => {
  const db = as('head');
  await assertSucceeds(updateDoc(doc(db, 'users', 'stu'), { role: 'Student Assistant' }));
  await assertSucceeds(updateDoc(doc(db, 'users', 'stu'), { status: 'Archived' }));
  await assertSucceeds(updateDoc(doc(db, 'users', 'stu'), { status: 'Active' }));
  // Not another role, and not deleting (an Admin's job).
  await assertFails(updateDoc(doc(db, 'users', 'stu'), { role: 'Admin' }));
  await assertFails(updateDoc(doc(db, 'users', 'stu'), { deleted: true }));
});

test('the Admin deletes an account by writing only its profile', async () => {
  await assertSucceeds(
    updateDoc(doc(as('admin'), 'users', 'stu'), { status: 'Archived', deleted: true }),
  );
  // And cannot touch the roster records the Head's session clears.
  await assertFails(deleteDoc(doc(as('admin'), 'students', 'stu')));
});

test('the Head moves an assistant between offices in one transaction', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'offices', 'o2'), {
      isActive: true,
      headIds: ['sup2'],
      assistantIds: [],
    });
  });
  const move = (db) =>
    runTransaction(db, async (tx) => {
      const from = await tx.get(doc(db, 'offices', 'o1'));
      const to = await tx.get(doc(db, 'offices', 'o2'));
      tx.set(doc(db, 'offices', 'o1'), { ...from.data(), assistantIds: [] });
      tx.set(doc(db, 'offices', 'o2'), { ...to.data(), assistantIds: ['sa'] });
    });
  await assertFails(move(as('sup')));
  await assertSucceeds(move(as('head')));
  const o2 = await getDoc(doc(as('head'), 'offices', 'o2'));
  assert.deepEqual(o2.data().assistantIds, ['sa']);
});

test('a placement reads and rewrites the person\'s assignment with the offices', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'officeAssignments', 'sa'), { officeId: 'o1' });
  });
  const place = (db) =>
    runTransaction(db, async (tx) => {
      const assignment = await tx.get(doc(db, 'officeAssignments', 'sa'));
      const old = await tx.get(doc(db, assignment.data() ? 'offices' : 'offices', assignment.data().officeId));
      tx.set(doc(db, 'offices', 'o1'), { ...old.data(), assistantIds: [] });
      tx.set(doc(db, 'officeAssignments', 'sa'), { officeId: 'o3' });
    });
  await assertFails(place(as('sup')));
  await assertSucceeds(place(as('head')));
});
