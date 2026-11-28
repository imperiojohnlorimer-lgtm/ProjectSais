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
  getDocs,
  collection,
  query,
  where,
  runTransaction,
  writeBatch,
  serverTimestamp,
  deleteField,
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

test('only a Student account can apply', async () => {
  for (const uid of ['sa', 'sup', 'admin', 'head']) {
    await assertFails(
      setDoc(doc(as(uid), 'applications', `app_${uid}_2026-2027`), application(uid)),
    );
  }
});

test('an account that stopped being a Student cannot replace a rejected application', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(
      doc(ctx.firestore(), 'applications', 'app_sa_2026-2027'),
      application('sa', { status: 'Rejected' }),
    );
  });
  await assertFails(
    setDoc(doc(as('sa'), 'applications', 'app_sa_2026-2027'), application('sa')),
  );
});

test('the Head still decides an application (keeps working)', async () => {
  await assertSucceeds(
    setDoc(doc(as('stu'), 'applications', 'app_stu_2026-2027'), application('stu')),
  );
  await assertSucceeds(
    updateDoc(doc(as('head'), 'applications', 'app_stu_2026-2027'), { status: 'For Screening' }),
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

test('a student can apply with a valid applicationForm map and is blocked on invalid ones', async () => {
  await assertFails(
    setDoc(
      doc(as('stu'), 'applications', 'app_stu_2026-2027'),
      application('stu', { applicationForm: 'not-a-map' }),
    ),
  );
  await assertFails(
    setDoc(
      doc(as('stu'), 'applications', 'app_stu_2026-2027'),
      application('stu', {
        applicationForm: {
          siblings: Array.from({ length: 21 }, (_, i) => ({ name: `Sib ${i}` })),
        },
      }),
    ),
  );
  await assertSucceeds(
    setDoc(
      doc(as('stu'), 'applications', 'app_stu_2026-2027'),
      application('stu', {
        applicationForm: {
          semester: '1st Sem',
          academicYear: '2026-2027',
          surname: 'Student',
          firstName: 'Sam',
          siblings: [{ name: 'Ana', age: '15', schoolOrOccupation: 'MarSU', program: 'SHS' }],
          organizations: [{ name: 'CS Society', position: 'Member' }],
        },
      }),
    ),
  );
});

// ── moving applications back after the Admin undid a year switch ────────

// The Admin moved to 2027-2028 and undid it; the year in effect is 2026-2027
// again. `stu` applied while 2027-2028 was in effect.
const seedUndoneYear = async ({ undone = '2027-2028', apps = {} } = {}) => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'meta', 'academic_year_settings'), {
      academicYear: '2026-2027',
      allowApplications: true,
      ...(undone ? { undoneAcademicYear: undone } : {}),
    });
    const all = {
      'app_stu_2027-2028': application('stu', { academicYear: '2027-2028' }),
      ...apps,
    };
    for (const [id, data] of Object.entries(all)) {
      await setDoc(doc(db, 'applications', id), data);
    }
  });
};

const moveApplication = (uid, fromId, toId, data) => {
  const db = as(uid);
  const batch = writeBatch(db);
  batch.set(doc(db, 'applications', toId), data);
  batch.delete(doc(db, 'applications', fromId));
  return batch.commit();
};

const moved = (over = {}) =>
  application('stu', { movedFrom: 'app_stu_2027-2028', ...over });

test('the Head moves an application out of the undone year (keeps working)', async () => {
  await seedUndoneYear();
  await assertSucceeds(
    moveApplication('head', 'app_stu_2027-2028', 'app_stu_2026-2027', moved()),
  );
});

test('the Head moves it in a transaction, as the app does (keeps working)', async () => {
  await seedUndoneYear();
  const db = as('head');
  const target = doc(db, 'applications', 'app_stu_2026-2027');
  await assertSucceeds(
    runTransaction(db, async (tx) => {
      const taken = await tx.get(target);
      assert.equal(taken.exists(), false);
      tx.set(target, moved());
      tx.delete(doc(db, 'applications', 'app_stu_2027-2028'));
    }),
  );
});

test('the Head cannot copy an application without deleting the old one', async () => {
  await seedUndoneYear();
  await assertFails(
    setDoc(doc(as('head'), 'applications', 'app_stu_2026-2027'), moved()),
  );
});

test('the Head cannot create an application without moving one', async () => {
  await seedUndoneYear();
  const { movedFrom, ...plain } = moved();
  await assertFails(
    moveApplication('head', 'app_stu_2027-2028', 'app_stu_2026-2027', plain),
  );
});

test('a moved application must stay unchanged', async () => {
  await seedUndoneYear();
  await assertFails(
    moveApplication(
      'head',
      'app_stu_2027-2028',
      'app_stu_2026-2027',
      moved({ status: 'Approved' }),
    ),
  );
});

test('an application moves only into the year in effect', async () => {
  await seedUndoneYear();
  await assertFails(
    moveApplication(
      'head',
      'app_stu_2027-2028',
      'app_stu_2028-2029',
      moved({ academicYear: '2028-2029' }),
    ),
  );
});

test('an application moves only out of the year the Admin undid', async () => {
  await seedUndoneYear({
    apps: {
      'app_stu_2025-2026': application('stu', { academicYear: '2025-2026' }),
    },
  });
  await assertFails(
    moveApplication(
      'head',
      'app_stu_2025-2026',
      'app_stu_2026-2027',
      moved({ movedFrom: 'app_stu_2025-2026' }),
    ),
  );
});

test('no application moves when no year switch was undone', async () => {
  await seedUndoneYear({ undone: null });
  await assertFails(
    moveApplication('head', 'app_stu_2027-2028', 'app_stu_2026-2027', moved()),
  );
});

test('the Head cannot move one applicant\'s application to another', async () => {
  await seedUndoneYear();
  await assertFails(
    moveApplication(
      'head',
      'app_stu_2027-2028',
      'app_sa_2026-2027',
      moved({ applicantId: 'sa', applicantName: accounts.sa.name }),
    ),
  );
});

// Only the Head may delete an application, so for anyone else the batch's
// delete is refused whatever the create rule says; isHead() in
// isHeadYearMove is a second line of defence that can't be tested apart.
test('only the Head moves applications', async () => {
  for (const uid of ['sup', 'admin', 'stu']) {
    await seedUndoneYear();
    await assertFails(
      moveApplication(uid, 'app_stu_2027-2028', 'app_stu_2026-2027', moved()),
    );
  }
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

test('nobody but the Head touches or reads the SA counter', async () => {
  await assertSucceeds(setDoc(doc(as('head'), 'meta', 'saCounter'), { next: 5 }));
  await assertSucceeds(getDoc(doc(as('head'), 'meta', 'saCounter')));
  for (const uid of ['sup', 'admin', 'sa', 'stu']) {
    await assertFails(getDoc(doc(as(uid), 'meta', 'saCounter')));
    await assertFails(setDoc(doc(as(uid), 'meta', 'saCounter'), { next: 99 }));
    await assertFails(allocateSaId(as(uid), 'stu'));
  }
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

// ── the day someone was accepted as a Student Assistant ──

test('the Head records the acceptance date; the student and a Supervisor cannot', async () => {
  const accepted = { acceptedAt: '2026-11-11T04:00:00.000Z' };
  await assertFails(updateDoc(doc(as('sa'), 'users', 'sa'), accepted));
  await assertFails(updateDoc(doc(as('sup'), 'users', 'sa'), accepted));
  await assertSucceeds(updateDoc(doc(as('head'), 'users', 'sa'), accepted));
  // Recorded, it isn't theirs to move or remove; their own details still change.
  await assertFails(updateDoc(doc(as('sa'), 'users', 'sa'), { acceptedAt: '2020-01-01T04:00:00.000Z' }));
  await assertFails(updateDoc(doc(as('sa'), 'users', 'sa'), { acceptedAt: deleteField() }));
  await assertSucceeds(updateDoc(doc(as('sa'), 'users', 'sa'), { phone: '0917 123 4567' }));
  // The Admin may correct it too.
  await assertSucceeds(updateDoc(doc(as('admin'), 'users', 'sa'), { acceptedAt: '2026-08-03T04:00:00.000Z' }));
});

test('a promotion carries the acceptance date in the same write', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users', 'applicant'), {
      name: 'Apple Cant',
      email: 'applicant@example.com',
      role: 'Student',
      status: 'Active',
    });
  });
  await assertSucceeds(
    updateDoc(doc(as('head'), 'users', 'applicant'), {
      role: 'Student Assistant',
      acceptedAt: '2026-11-11T04:00:00.000Z',
    }),
  );
});

test('a new account cannot give itself an acceptance date', async () => {
  await assertFails(
    setDoc(doc(as('fresh'), 'users', 'fresh'), newAccount({ acceptedAt: '2026-11-11T04:00:00.000Z' })),
  );
});

// ── the Privacy Notice acceptance ──

const newAccount = (over = {}) => ({
  name: 'New Person',
  email: 'fresh@example.com',
  role: 'Student',
  status: 'Active',
  consentAt: '2026-10-26T01:02:03.000Z',
  consentVersion: '2026-10-draft',
  ...over,
});

test('a new account records when it accepted the notice', async () => {
  await assertSucceeds(setDoc(doc(as('fresh'), 'users', 'fresh'), newAccount()));
});

test('registering without accepting the notice is refused; the Admin may make an account without it', async () => {
  const bare = newAccount();
  delete bare.consentAt;
  delete bare.consentVersion;
  await assertFails(setDoc(doc(as('fresh'), 'users', 'fresh'), bare));
  await assertFails(
    setDoc(doc(as('fresh'), 'users', 'fresh'), { ...bare, consentAt: null, consentVersion: null }),
  );
  await assertSucceeds(setDoc(doc(as('admin'), 'users', 'made-by-admin'), bare));
});

test('neither the Admin nor the Head rewrites a recorded acceptance', async () => {
  await assertSucceeds(setDoc(doc(as('fresh'), 'users', 'fresh'), newAccount()));
  for (const who of ['admin', 'head']) {
    await assertFails(updateDoc(doc(as(who), 'users', 'fresh'), { consentAt: '2030-01-01T00:00:00.000Z' }));
    await assertFails(updateDoc(doc(as(who), 'users', 'fresh'), { consentVersion: 'other' }));
  }
  await assertSucceeds(updateDoc(doc(as('admin'), 'users', 'fresh'), { phone: '0917 123 4567' }));
});

test('the recorded acceptance must be short text', async () => {
  await assertFails(setDoc(doc(as('fresh'), 'users', 'fresh'), newAccount({ consentAt: 12345 })));
  await assertFails(
    setDoc(doc(as('fresh'), 'users', 'fresh'), newAccount({ consentVersion: 'v'.repeat(80) })),
  );
});

test('nobody edits their own acceptance afterwards', async () => {
  const db = as('fresh');
  await assertSucceeds(setDoc(doc(db, 'users', 'fresh'), newAccount()));
  await assertFails(updateDoc(doc(db, 'users', 'fresh'), { consentAt: '2030-01-01T00:00:00.000Z' }));
  await assertFails(updateDoc(doc(db, 'users', 'fresh'), { consentVersion: 'other' }));
  // Their other details still change.
  await assertSucceeds(updateDoc(doc(db, 'users', 'fresh'), { phone: '0917 123 4567' }));
});

test('an account that has none cannot give itself one', async () => {
  await assertFails(updateDoc(doc(as('stu'), 'users', 'stu'), { consentAt: '2026-10-26T00:00:00.000Z' }));
});

// ── a Student Assistant's own payroll check ──

test('a Student Assistant reads their own payroll check, nobody else\'s', async () => {
  const check = (id) => ({ studentId: id, studentName: id, items: {}, exclusions: {} });
  await assertSucceeds(setDoc(doc(as('head'), 'payrollChecks', 'sa'), check('sa')));
  await assertSucceeds(setDoc(doc(as('head'), 'payrollChecks', 'other'), check('other')));

  await assertSucceeds(getDoc(doc(as('sa'), 'payrollChecks', 'sa')));
  await assertFails(getDoc(doc(as('sa'), 'payrollChecks', 'other')));
  // Reading is all they may do.
  await assertFails(setDoc(doc(as('sa'), 'payrollChecks', 'sa'), check('sa')));
  await assertFails(deleteDoc(doc(as('sa'), 'payrollChecks', 'sa')));
});

// ── a report cannot arrive looking reviewed ──

test('a report is made Pending and unreviewed', async () => {
  const report = (extra = {}) => ({
    applicantId: 'sa',
    title: 'Week 1',
    content: 'Did things',
    studentName: 'Sia Assistant',
    status: 'Pending',
    ...extra,
  });
  await assertSucceeds(setDoc(doc(as('sa'), 'reports', 'r1'), report()));
  await assertFails(
    setDoc(doc(as('sa'), 'reports', 'r2'), report({ reviewedBy: 'Sam Supervisor' })),
  );
  await assertFails(
    setDoc(doc(as('sa'), 'reports', 'r3'), report({ reviewedAt: '2026-10-01T00:00:00.000Z' })),
  );
});

// ── queries the app tries as fallbacks ─────────────────────────────────

test('a student\'s own queries work; the by-name fallbacks are refused', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'reports', 'r1'), {
      applicantId: 'stu',
      studentName: 'Stu Student',
      status: 'Pending',
    });
    await setDoc(doc(db, 'tasks', 't1'), {
      assignedTo: 'stu',
      assignedToName: 'Stu Student',
    });
  });
  const db = as('stu');
  // What the app relies on...
  await assertSucceeds(getDocs(query(collection(db, 'reports'), where('applicantId', '==', 'stu'))));
  await assertSucceeds(getDocs(query(collection(db, 'tasks'), where('assignedTo', '==', 'stu'))));
  // ...and the legacy by-name lookups, which the app treats as optional
  // (AppState._optionalLoads) because no rule can tie a name to an account.
  await assertFails(getDocs(query(collection(db, 'reports'), where('studentName', '==', 'Stu Student'))));
  await assertFails(getDocs(query(collection(db, 'tasks'), where('assignedToName', '==', 'Stu Student'))));
});

// ── the live queries each role opens (AppState._startLiveData) ──────────
// A refused one is reported to the user as a problem, so a query a role
// opens as a matter of course must be allowed.

const everyone = ['offices', 'departments', 'programs', 'skills', 'announcements'];
const rosterReads = [
  'users', 'students', 'reports', 'attendance', 'tasks', 'headForwards',
  'evaluations', 'documents', 'classSchedules', 'taskDuties',
];

async function reads(uid, collections) {
  const db = as(uid);
  for (const name of collections) {
    await assertSucceeds(getDocs(collection(db, name)));
  }
  for (const id of ['academic_year_settings', 'task_categories', 'task_templates']) {
    if (uid === 'sa' || uid === 'stu') {
      if (id !== 'academic_year_settings') continue;
    }
    await assertSucceeds(getDoc(doc(db, 'meta', id)));
  }
}

test('the Head\'s live queries are all allowed', async () => {
  await reads('head', [
    ...everyone, ...rosterReads,
    'applications', 'payrollChecks', 'rehireRecords', 'screeningRecords',
  ]);
});

test('a Supervisor\'s live queries are allowed (applications are the Head\'s)', async () => {
  await reads('sup', [...everyone, ...rosterReads]);
  await assertFails(getDocs(collection(as('sup'), 'applications')));
});

test('the Admin\'s live queries are all allowed', async () => {
  await reads('admin', [
    ...everyone, 'users', 'students', 'reports', 'attendance',
    'payrollChecks', 'payrollRecords', 'payrollSheets',
  ]);
});

test('a Student Assistant\'s own live queries are allowed', async () => {
  const db = as('sa');
  await reads('sa', everyone);
  await assertSucceeds(getDocs(query(collection(db, 'attendance'), where('studentId', '==', 'sa'))));
  await assertSucceeds(getDocs(query(collection(db, 'applications'), where('applicantId', '==', 'sa'))));
  await assertSucceeds(getDocs(query(collection(db, 'payrollRecords'), where('studentId', '==', 'sa'))));
  await assertSucceeds(getDocs(query(collection(db, 'taskDuties'), where('assignedTo', '==', 'sa'))));
  await assertSucceeds(getDocs(query(collection(db, 'classSchedules'), where('studentId', '==', 'sa'))));
  await assertSucceeds(getDocs(query(collection(db, 'notifications'), where('userId', '==', 'sa'))));
  await assertSucceeds(getDocs(query(collection(db, 'reports'), where('applicantId', '==', 'sa'))));
});

test('a Student\'s own live queries are allowed', async () => {
  const db = as('stu');
  await reads('stu', everyone);
  await assertSucceeds(getDocs(query(collection(db, 'applications'), where('applicantId', '==', 'stu'))));
  await assertSucceeds(getDocs(query(collection(db, 'notifications'), where('userId', '==', 'stu'))));
});

test('tasks given to a student\'s roster record are found by that record\'s id', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'students', 's1'), { userId: 'stu', name: 'Stu Student' });
    await setDoc(doc(db, 'tasks', 't9'), { assignedTo: 's1', title: 'Shelve books' });
  });
  await assertSucceeds(
    getDocs(query(collection(as('stu'), 'tasks'), where('assignedTo', 'in', ['s1']))),
  );
});

// ── email notifications (the switch on a profile) ──────────────────────

test('a person turns their own email notifications off and on', async () => {
  const db = as('sa');
  await assertSucceeds(updateDoc(doc(db, 'users', 'sa'), { emailNotifications: false }));
  await assertSucceeds(updateDoc(doc(db, 'users', 'sa'), { emailNotifications: true }));
});

test('the setting must be true or false', async () => {
  for (const bad of ['no', 0, 'false', ['x']]) {
    await assertFails(updateDoc(doc(as('sa'), 'users', 'sa'), { emailNotifications: bad }));
  }
});

test('nobody else changes it, the Admin and the Head included', async () => {
  for (const uid of ['admin', 'head', 'stu', 'sup']) {
    await assertFails(
      updateDoc(doc(as(uid), 'users', 'sa'), { emailNotifications: false }),
    );
  }
});

test('the Admin and the Head still edit a profile that holds the setting', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'users', 'sa'), { emailNotifications: false });
  });
  await assertSucceeds(updateDoc(doc(as('admin'), 'users', 'sa'), { department: 'Education' }));
  await assertSucceeds(updateDoc(doc(as('head'), 'users', 'sa'), { skills: ['Typing'] }));
});

test('an older profile without the setting saves as before (Admin)', async () => {
  await assertSucceeds(updateDoc(doc(as('admin'), 'users', 'sa'), { department: 'Education' }));
});

// ── programs: adding several at once (one atomic batch) ─────────────────

const programDoc = (code, over = {}) => ({
  code,
  name: 'Program ' + code,
  department: 'College of Engineering',
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  ...over,
});

function programBatch(db, docs) {
  const batch = writeBatch(db);
  docs.forEach((data, i) => batch.set(doc(db, 'programs', 'new' + i), data));
  return batch;
}

test('the Admin adds several programs in one batch', async () => {
  const batch = programBatch(as('admin'), [
    programDoc('BSCS'), programDoc('BSEE'), programDoc('BSIS'),
  ]);
  await assertSucceeds(batch.commit());
  const all = await getDocs(collection(as('admin'), 'programs'));
  assert.equal(all.size, 3);
});

test('a batch of fifty programs is allowed', async () => {
  const batch = programBatch(
    as('admin'),
    Array.from({ length: 50 }, (_, i) => programDoc('C' + i)),
  );
  await assertSucceeds(batch.commit());
});

test('nobody else adds programs, in a batch or one at a time', async () => {
  for (const uid of ['head', 'sup', 'sa', 'stu']) {
    await assertFails(programBatch(as(uid), [programDoc('BSCS')]).commit());
  }
  const signedOut = env.unauthenticatedContext().firestore();
  await assertFails(programBatch(signedOut, [programDoc('BSCS')]).commit());
  await assertFails(setDoc(doc(as('head'), 'programs', 'solo'), programDoc('BSCS')));
});

test('one program with an extra field refuses the whole batch', async () => {
  const batch = programBatch(as('admin'), [
    programDoc('BSCS'),
    programDoc('BSEE', { isAdmin: true }),
    programDoc('BSIS'),
  ]);
  await assertFails(batch.commit());
  const all = await getDocs(collection(as('admin'), 'programs'));
  assert.equal(all.size, 0, 'nothing from the refused batch may be saved');
});

// ── staff sign-ups that wait for the Head ────────────────────────────────

const asUnverified = (uid) =>
  env
    .authenticatedContext(uid, { email: `${uid}@example.com`, email_verified: false })
    .firestore();

const staffRequest = (over = {}) => ({
  name: 'Pat Pending',
  email: 'pend@example.com',
  role: 'Student',
  status: 'Pending',
  requestedRole: 'Supervisor',
  department: 'College of Engineering',
  consentAt: '2026-10-26T01:02:03.000Z',
  consentVersion: '2026-10-draft',
  ...over,
});

/** A staff request as registration saves it, ready to be decided. */
async function seedPending(over = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users', 'pend'), staffRequest(over));
  });
}

const approve = (requested) => ({
  role: requested,
  status: 'Active',
  requestedRole: deleteField(),
});

test('someone registers a request for the Supervisor or Head role, Pending and powerless', async () => {
  for (const requestedRole of ['Supervisor', 'Head']) {
    await env.clearFirestore();
    await assertSucceeds(
      setDoc(doc(asUnverified('pend'), 'users', 'pend'), staffRequest({ requestedRole })),
    );
  }
});

test('a request cannot claim a staff role, Admin, or skip the waiting', async () => {
  const db = asUnverified('pend');
  for (const bad of [
    { requestedRole: 'Admin' },
    { requestedRole: 'Student Assistant' },
    { requestedRole: 'Student' },
    { requestedRole: undefined },
    { role: 'Supervisor' },
    { role: 'Admin' },
    { status: 'Active' },
    { status: 'Declined' },
  ]) {
    const data = staffRequest(bad);
    for (const k of Object.keys(data)) if (data[k] === undefined) delete data[k];
    await assertFails(setDoc(doc(db, 'users', 'pend'), data));
  }
  // An ordinary Active student may not carry a requested role either.
  await assertFails(
    setDoc(doc(db, 'users', 'pend'), staffRequest({ status: 'Active' })),
  );
});

test('a waiting request has no access, but can read its own profile to be told why', async () => {
  await seedPending();
  const db = as('pend');
  await assertSucceeds(getDoc(doc(db, 'users', 'pend')));
  await assertFails(getDoc(doc(db, 'users', 'sa')));
  await assertFails(getDocs(collection(db, 'tasks')));
  await assertFails(updateDoc(doc(db, 'users', 'pend'), { phone: '0917 123 4567' }));
  await assertFails(updateDoc(doc(db, 'users', 'pend'), { status: 'Active' }));
  await assertFails(updateDoc(doc(db, 'users', 'pend'), { role: 'Supervisor' }));
});

test('the Head approves a request: it gets the role it asked for and becomes Active', async () => {
  for (const requested of ['Supervisor', 'Head']) {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'users', 'head'), { name: 'Hana Head', role: 'Head', status: 'Active', email: 'head@example.com' });
    });
    await seedPending({ requestedRole: requested });
    await assertSucceeds(updateDoc(doc(as('head'), 'users', 'pend'), approve(requested)));
    // Now a working account of that role: staff may read profiles.
    await assertSucceeds(getDoc(doc(as('pend'), 'users', 'stu')));
  }
});

test('the Head declines a request, and a declined one stays locked out', async () => {
  await seedPending();
  await assertSucceeds(updateDoc(doc(as('head'), 'users', 'pend'), { status: 'Declined' }));
  await assertFails(getDoc(doc(as('pend'), 'users', 'stu')));
  // Nobody approves it afterwards through the Head's rule.
  await assertFails(updateDoc(doc(as('head'), 'users', 'pend'), approve('Supervisor')));
});

test('the Head cannot approve to another role or change anything else', async () => {
  await seedPending({ requestedRole: 'Supervisor' });
  const head = as('head');
  for (const bad of [
    { ...approve('Supervisor'), role: 'Admin' },
    { ...approve('Supervisor'), role: 'Head' },
    { ...approve('Supervisor'), phone: '0917 123 4567' },
    { ...approve('Supervisor'), email: 'other@example.com' },
    { ...approve('Supervisor'), department: 'Anywhere' },
    { ...approve('Supervisor'), consentAt: '2030-01-01T00:00:00.000Z' },
    { role: 'Supervisor', status: 'Active' }, // leaves requestedRole behind
    { status: 'Active' },
    { status: 'Declined', phone: '0917 123 4567' },
    { status: 'Declined', role: 'Supervisor' },
    { status: 'Archived' },
    { requestedRole: 'Head' },
  ]) {
    await assertFails(updateDoc(doc(head, 'users', 'pend'), bad));
  }
});

test('only a Head (or the Admin) decides, and only on a waiting request', async () => {
  await seedPending();
  for (const who of ['sup', 'sa', 'stu', 'pend']) {
    await assertFails(updateDoc(doc(as(who), 'users', 'pend'), approve('Supervisor')));
    await assertFails(updateDoc(doc(as(who), 'users', 'pend'), { status: 'Declined' }));
  }
  // The Head cannot turn an ordinary account into staff this way.
  await assertFails(updateDoc(doc(as('head'), 'users', 'stu'), approve('Supervisor')));
  await assertFails(updateDoc(doc(as('head'), 'users', 'sa'), approve('Head')));
  // The Admin still can.
  await assertSucceeds(updateDoc(doc(as('admin'), 'users', 'pend'), approve('Supervisor')));
});

test('a Head still archives and restores students, but not a waiting request as a student', async () => {
  await assertSucceeds(updateDoc(doc(as('head'), 'users', 'stu'), { status: 'Archived' }));
  await assertSucceeds(updateDoc(doc(as('head'), 'users', 'stu'), { status: 'Active' }));
  await seedPending();
  await assertFails(updateDoc(doc(as('head'), 'users', 'pend'), { status: 'Active' }));
});

// ── Supervisor cards: the name and picture a Student Assistant sees on My Office
const card = (over = {}) => ({
  name: 'Sam Supervisor',
  avatar: 'data:image/png;base64,AAAA',
  updatedAt: serverTimestamp(),
  ...over,
});

test('a Supervisor writes only their own card, with exactly name, avatar and updatedAt', async () => {
  const sup = as('sup');
  await assertSucceeds(setDoc(doc(sup, 'supervisorCards', 'sup'), card()));
  await assertSucceeds(
    setDoc(doc(sup, 'supervisorCards', 'sup'), card({ avatar: '' })),
  );
  // Not another supervisor's, and nothing extra or missing.
  await assertFails(setDoc(doc(sup, 'supervisorCards', 'sup2'), card()));
  await assertFails(
    setDoc(doc(sup, 'supervisorCards', 'sup'), card({ email: 'sup@example.com' })),
  );
  await assertFails(
    setDoc(doc(sup, 'supervisorCards', 'sup'), { name: 'Sam', avatar: '' }),
  );
  await assertFails(
    setDoc(doc(sup, 'supervisorCards', 'sup'), card({ updatedAt: new Date(0) })),
  );
  await assertFails(
    setDoc(doc(sup, 'supervisorCards', 'sup'), card({ avatar: 42 })),
  );
});

test('a Student Assistant or Student cannot write a card, but anyone signed in reads one', async () => {
  for (const who of ['sa', 'stu']) {
    await assertFails(setDoc(doc(as(who), 'supervisorCards', who), card()));
    await assertFails(setDoc(doc(as(who), 'supervisorCards', 'sup'), card()));
  }
  await assertSucceeds(setDoc(doc(as('sup'), 'supervisorCards', 'sup'), card()));
  for (const who of ['sa', 'stu', 'sup2', 'head', 'admin']) {
    await assertSucceeds(getDoc(doc(as(who), 'supervisorCards', 'sup')));
  }
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'supervisorCards', 'sup')));
});

test('the Head and the Admin keep any Supervisor card in step, and may remove one', async () => {
  await assertSucceeds(setDoc(doc(as('head'), 'supervisorCards', 'sup'), card()));
  await assertSucceeds(
    setDoc(doc(as('admin'), 'supervisorCards', 'sup2'), card({ name: 'Sol Supervisor' })),
  );
  await assertFails(deleteDoc(doc(as('sup'), 'supervisorCards', 'sup')));
  await assertFails(deleteDoc(doc(as('sa'), 'supervisorCards', 'sup')));
  await assertSucceeds(deleteDoc(doc(as('head'), 'supervisorCards', 'sup')));
  await assertSucceeds(deleteDoc(doc(as('admin'), 'supervisorCards', 'sup2')));
});

test('a Student Assistant still cannot read a supervisor profile', async () => {
  await assertFails(getDoc(doc(as('sa'), 'users', 'sup')));
});

// ── class schedules ───────────────────────────────────────────────────

const subject = { id: 's1', label: 'Math 1', weekday: 1, startHour: 8, startMinute: 0, endHour: 9, endMinute: 0, isSubject: true };
const version = { id: 'cs1', effectiveFrom: '2026-11-01', subjects: [subject], filePath: 'schedules/sa/1/a.png', source: 'request' };

const scheduleRequest = (over = {}) => ({
  id: 'sa_1700000000000',
  studentId: 'sa',
  studentName: 'Sia Assistant',
  academicYear: '2026-2027',
  fileName: 'sched.png',
  filePath: 'schedules/sa/1700000000000/abc.png',
  subjects: [subject],
  effectiveFrom: '2026-11-20',
  note: '',
  status: 'Pending',
  submittedAt: serverTimestamp(),
  ...over,
});

test('an assistant and their Supervisor still save weekly rules (keeps working)', async () => {
  await assertSucceeds(
    setDoc(doc(as('sa'), 'recurringSchedules', 'sa'), { ownerId: 'sa', ownerName: 'Sia Assistant', rules: [] }),
  );
  await assertSucceeds(
    setDoc(doc(as('sup'), 'recurringSchedules', 'sa'), { ownerId: 'sa', ownerName: 'Sia Assistant', rules: [subject] }, { merge: true }),
  );
});

test('only the Head writes approved class schedules', async () => {
  // Not on a new document...
  await assertFails(
    setDoc(doc(as('sa'), 'recurringSchedules', 'sa'), { ownerId: 'sa', classSchedules: [version] }),
  );
  await assertFails(
    setDoc(doc(as('sup'), 'recurringSchedules', 'sa'), { ownerId: 'sa', classSchedules: [version] }),
  );
  await assertSucceeds(
    setDoc(doc(as('head'), 'recurringSchedules', 'sa'), { ownerId: 'sa', ownerName: 'Sia Assistant', rules: [], classSchedules: [version] }),
  );
  // ...nor by changing them on one that has them, nor deleting it.
  await assertFails(
    updateDoc(doc(as('sa'), 'recurringSchedules', 'sa'), { classSchedules: [] }),
  );
  await assertFails(
    updateDoc(doc(as('sup'), 'recurringSchedules', 'sa'), { classSchedules: [] }),
  );
  await assertFails(deleteDoc(doc(as('sa'), 'recurringSchedules', 'sa')));
  await assertFails(deleteDoc(doc(as('sup'), 'recurringSchedules', 'sa')));
  // Saving the weekly rules beside them still works.
  await assertSucceeds(
    setDoc(doc(as('sa'), 'recurringSchedules', 'sa'), { ownerId: 'sa', ownerName: 'Sia Assistant', rules: [] }, { merge: true }),
  );
  // A whole-document save (an older app) would drop them: refused.
  await assertFails(
    setDoc(doc(as('sa'), 'recurringSchedules', 'sa'), { ownerId: 'sa', ownerName: 'Sia Assistant', rules: [] }),
  );
  await assertSucceeds(
    updateDoc(doc(as('head'), 'recurringSchedules', 'sa'), { classSchedules: [version, { ...version, id: 'cs2' }] }),
  );
});

test('an assistant sends a new schedule for themselves only', async () => {
  await assertSucceeds(setDoc(doc(as('sa'), 'scheduleRequests', 'sa_1700000000000'), scheduleRequest()));
  // Not for someone else, not as a Student, not already decided, not with
  // a file outside their own folder, not with a made-up time or extra field.
  await assertFails(
    setDoc(doc(as('sa'), 'scheduleRequests', 'stu_1700000000001'), scheduleRequest({ id: 'stu_1700000000001', studentId: 'stu' })),
  );
  await assertFails(
    setDoc(doc(as('stu'), 'scheduleRequests', 'stu_1700000000002'), scheduleRequest({ id: 'stu_1700000000002', studentId: 'stu', studentName: 'Stu Student', filePath: 'schedules/stu/1/a.png' })),
  );
  await assertFails(
    setDoc(doc(as('sa'), 'scheduleRequests', 'sa_1700000000003'), scheduleRequest({ id: 'sa_1700000000003', status: 'Approved' })),
  );
  await assertFails(
    setDoc(doc(as('sa'), 'scheduleRequests', 'sa_1700000000004'), scheduleRequest({ id: 'sa_1700000000004', filePath: 'schedules/stu/1/a.png' })),
  );
  await assertFails(
    setDoc(doc(as('sa'), 'scheduleRequests', 'sa_1700000000005'), scheduleRequest({ id: 'sa_1700000000005', submittedAt: '2020-01-01' })),
  );
  await assertFails(
    setDoc(doc(as('sa'), 'scheduleRequests', 'sa_1700000000006'), scheduleRequest({ id: 'sa_1700000000006', reviewedBy: 'Me' })),
  );
  // Read by the student and the Head, not by others.
  await assertSucceeds(getDoc(doc(as('sa'), 'scheduleRequests', 'sa_1700000000000')));
  await assertSucceeds(getDoc(doc(as('head'), 'scheduleRequests', 'sa_1700000000000')));
  await assertFails(getDoc(doc(as('sup'), 'scheduleRequests', 'sa_1700000000000')));
  await assertFails(getDoc(doc(as('stu'), 'scheduleRequests', 'sa_1700000000000')));
});

test('the student withdraws a waiting request; only the Head decides one', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'scheduleRequests', 'r1'), scheduleRequest({ id: 'r1', submittedAt: '2026-11-19' }));
    await setDoc(doc(ctx.firestore(), 'scheduleRequests', 'r2'), scheduleRequest({ id: 'r2', submittedAt: '2026-11-19' }));
  });
  await assertFails(updateDoc(doc(as('sa'), 'scheduleRequests', 'r1'), { status: 'Approved' }));
  await assertFails(updateDoc(doc(as('sup'), 'scheduleRequests', 'r1'), { status: 'Approved' }));
  await assertFails(updateDoc(doc(as('head'), 'scheduleRequests', 'r1'), { status: 'Approved', subjects: [] }));
  await assertSucceeds(updateDoc(doc(as('sa'), 'scheduleRequests', 'r1'), { status: 'Cancelled' }));
  // Withdrawn: nobody decides it now.
  await assertFails(updateDoc(doc(as('head'), 'scheduleRequests', 'r1'), { status: 'Approved' }));
  await assertSucceeds(
    updateDoc(doc(as('head'), 'scheduleRequests', 'r2'), { status: 'Rejected', reviewNote: 'Wrong file', reviewedBy: 'Hana Head', reviewedAt: '2026-11-19T00:00:00Z' }),
  );
  await assertFails(updateDoc(doc(as('sa'), 'scheduleRequests', 'r2'), { status: 'Cancelled' }));
  await assertFails(deleteDoc(doc(as('head'), 'scheduleRequests', 'r2')));
});

test('the Head approves a request and the schedule in one transaction', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'scheduleRequests', 'r3'), scheduleRequest({ id: 'r3', submittedAt: '2026-11-19' }));
  });
  const db = as('head');
  await assertSucceeds(
    runTransaction(db, async (tx) => {
      await tx.get(doc(db, 'recurringSchedules', 'sa'));
      await tx.get(doc(db, 'scheduleRequests', 'r3'));
      tx.set(doc(db, 'recurringSchedules', 'sa'), { ownerId: 'sa', ownerName: 'Sia Assistant', rules: [], classSchedules: [version] }, { merge: true });
      tx.update(doc(db, 'scheduleRequests', 'r3'), { status: 'Approved', reviewedBy: 'Hana Head', reviewedAt: '2026-11-19T00:00:00Z' });
    }),
  );
});

test('an assistant tells the Head about a new schedule', async () => {
  await assertSucceeds(
    setDoc(doc(as('sa'), 'notifications', 'n_sched'), {
      userId: 'head', title: 'Schedule Change Request', message: 'Sia Assistant sent a new class schedule for approval.', type: 'schedule', isRead: false,
    }),
  );
  await assertFails(
    setDoc(doc(as('sa'), 'notifications', 'n_sched2'), {
      userId: 'stu', title: 'x', message: 'y', type: 'schedule', isRead: false,
    }),
  );
});

test('an application carries its class schedule from the applicant\'s own folder', async () => {
  const schedule = { fileName: 'a.png', filePath: 'schedules/stu/1700/a.png', subjects: [subject] };
  await assertSucceeds(
    setDoc(doc(as('stu'), 'applications', 'app_stu_2026-2027'), application('stu', { classSchedule: schedule })),
  );
});

test('an application\'s class schedule must be the applicant\'s own file', async () => {
  await assertFails(
    setDoc(
      doc(as('stu'), 'applications', 'app_stu_2026-2027'),
      application('stu', { classSchedule: { fileName: 'a.png', filePath: 'schedules/sa/1700/a.png', subjects: [] } }),
    ),
  );
  await assertFails(
    setDoc(
      doc(as('stu'), 'applications', 'app_stu_2026-2027'),
      application('stu', { classSchedule: { fileName: 'a.png', filePath: 'schedules/stu/1700/a.png', subjects: [], extra: 1 } }),
    ),
  );
});

// ── Student ID on the application, checked by the Head ─────────────────

test('an application carries a Student ID in the 23B0626 shape', async () => {
  await assertSucceeds(
    setDoc(doc(as('stu'), 'applications', 'app_stu_2026-2027'), application('stu', { studentNumber: '23B0626' })),
  );
});

test('a badly shaped Student ID is refused', async () => {
  for (const studentNumber of ['23b0626', '230626', '23B06266', '', 7]) {
    await assertFails(
      setDoc(doc(as('stu'), 'applications', 'app_stu_2026-2027'), application('stu', { studentNumber })),
    );
  }
});

test('the applicant cannot mark their own Student ID as checked', async () => {
  await assertFails(
    setDoc(
      doc(as('stu'), 'applications', 'app_stu_2026-2027'),
      application('stu', { studentNumber: '23B0626', studentIdCheckedBy: 'Stu Student' }),
    ),
  );
  await assertFails(
    setDoc(
      doc(as('stu'), 'applications', 'app_stu_2026-2027'),
      application('stu', { studentNumber: '23B0626', studentIdCheckedAt: '2026-11-21T00:00:00Z' }),
    ),
  );
});

test('a profile with a valid Student ID applies with that one only', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'users', 'stu'), { studentId: '23b0626 ' });
  });
  await assertFails(
    setDoc(doc(as('stu'), 'applications', 'app_stu_2026-2027'), application('stu', { studentNumber: '24C1111' })),
  );
  await assertSucceeds(
    setDoc(doc(as('stu'), 'applications', 'app_stu_2026-2027'), application('stu', { studentNumber: '23B0626' })),
  );
});

test('an older Student ID in another shape does not block applying', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'users', 'stu'), { studentId: '2023-0626' });
  });
  await assertSucceeds(
    setDoc(doc(as('stu'), 'applications', 'app_stu_2026-2027'), application('stu', { studentNumber: '23B0626' })),
  );
});

test('the Head marks the Student ID as checked', async () => {
  await assertSucceeds(
    setDoc(doc(as('stu'), 'applications', 'app_stu_2026-2027'), application('stu', { studentNumber: '23B0626' })),
  );
  await assertSucceeds(
    updateDoc(doc(as('head'), 'applications', 'app_stu_2026-2027'), {
      studentIdCheckedBy: 'Hana Head',
      studentIdCheckedAt: '2026-11-21T00:00:00Z',
    }),
  );
});

test('nobody verifies their own Student ID on their profile', async () => {
  await assertFails(
    updateDoc(doc(as('stu'), 'users', 'stu'), { studentIdVerifiedAt: '2026-11-21T00:00:00Z' }),
  );
  await assertFails(
    updateDoc(doc(as('stu'), 'users', 'stu'), { studentIdVerifiedBy: 'Stu Student' }),
  );
});

test('a verified student still edits their own contact details', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'users', 'stu'), {
      studentId: '23B0626',
      studentIdVerifiedAt: '2026-11-21T00:00:00Z',
      studentIdVerifiedBy: 'Hana Head',
    });
  });
  await assertSucceeds(updateDoc(doc(as('stu'), 'users', 'stu'), { phone: '0917 123 4567' }));
});

test('a new account cannot arrive with a verified Student ID', async () => {
  const profile = {
    name: 'New Person',
    email: 'newbie@example.com',
    role: 'Student',
    status: 'Active',
    consentAt: '2026-11-21T00:00:00Z',
    consentVersion: '2026-11-draft',
    studentIdVerifiedAt: '2026-11-21T00:00:00Z',
  };
  const db = env
    .authenticatedContext('newbie', { email: 'newbie@example.com', email_verified: false })
    .firestore();
  await assertFails(setDoc(doc(db, 'users', 'newbie'), profile));
  delete profile.studentIdVerifiedAt;
  await assertSucceeds(setDoc(doc(db, 'users', 'newbie'), profile));
});

test('the Head puts a checked Student ID on the profile and reserves it, in one transaction', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'users', 'stu'), { role: 'Student Assistant' });
  });
  const db = as('head');
  await assertSucceeds(
    runTransaction(db, async (tx) => {
      const claim = doc(db, 'studentIds', '23B0626');
      await tx.get(claim);
      tx.set(claim, { uid: 'stu' });
      tx.update(doc(db, 'users', 'stu'), {
        studentId: '23B0626',
        studentIdVerifiedAt: '2026-11-21T00:00:00Z',
        studentIdVerifiedBy: 'Hana Head',
      });
    }),
  );
});

test('a profile saved with no Student ID (null) applies with any well-shaped one', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'users', 'stu'), { studentId: null });
  });
  await assertSucceeds(
    setDoc(doc(as('stu'), 'applications', 'app_stu_2026-2027'), application('stu', { studentNumber: '23B0626' })),
  );
});

// ── attendance QR codes, one per office ────────────────────────────────

const qrCode = (over = {}) => ({
  token: 'SAIS-ATT-20261127-AM-0123456789abcdef0123456789abcdef',
  sessionKey: '20261127-AM',
  generatedAt: serverTimestamp(),
  officeName: 'Library',
  ...over,
});

// The generator's own write: read the office's code, keep it if it is this
// session's, else save a new one, in one transaction.
const claimQr = (db, officeId, over = {}) =>
  runTransaction(db, async (tx) => {
    const ref = doc(db, 'attendanceQr', officeId);
    const saved = await tx.get(ref);
    if (saved.exists() && saved.data().sessionKey === (over.sessionKey ?? '20261127-AM')) {
      return saved.data();
    }
    tx.set(ref, qrCode(over));
    return null;
  });

const seedQr = (officeId, data) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'attendanceQr', officeId), data);
  });

test("an office's supervisor saves and reads its code in the generator's transaction", async () => {
  await assertSucceeds(claimQr(as('sup'), 'o1'));
  await assertSucceeds(getDoc(doc(as('sup'), 'attendanceQr', 'o1')));
});

test('a second supervisor of the same office reads the code', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'offices', 'o1'), {
      isActive: true,
      headIds: ['sup', 'sup2'],
      assistantIds: ['sa'],
    });
  });
  await assertSucceeds(claimQr(as('sup'), 'o1'));
  await assertSucceeds(getDoc(doc(as('sup2'), 'attendanceQr', 'o1')));
});

test("nobody else reads or writes an office's code", async () => {
  await seedQr('o1', { ...qrCode(), generatedAt: new Date() });
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'offices', 'o2'), {
      isActive: true,
      headIds: ['sup2'],
      assistantIds: [],
    });
  });
  for (const uid of ['sup2', 'head', 'admin', 'sa', 'stu']) {
    await assertFails(getDoc(doc(as(uid), 'attendanceQr', 'o1')));
    await assertFails(setDoc(doc(as(uid), 'attendanceQr', 'o1'), qrCode({ sessionKey: '20261127-PM' })));
  }
  // Heading o1 gives nothing over o2's code, nor over an office that doesn't exist.
  await assertFails(setDoc(doc(as('sup'), 'attendanceQr', 'o2'), qrCode()));
  await assertFails(setDoc(doc(as('sup'), 'attendanceQr', 'nowhere'), qrCode()));
});

test("an inactive office's supervisor can't post a code", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'offices', 'o1'), {
      isActive: false,
      headIds: ['sup'],
      assistantIds: ['sa'],
    });
  });
  await assertFails(setDoc(doc(as('sup'), 'attendanceQr', 'o1'), qrCode()));
  await assertFails(getDoc(doc(as('sup'), 'attendanceQr', 'o1')));
});

test('a code must have exactly its four fields, in shape', async () => {
  const db = as('sup');
  const ref = doc(db, 'attendanceQr', 'o1');
  await assertFails(setDoc(ref, qrCode({ extra: true })));
  const { officeName, ...noName } = qrCode();
  await assertFails(setDoc(ref, noName));
  await assertFails(setDoc(ref, qrCode({ token: 'SHORT' })));
  await assertFails(setDoc(ref, qrCode({ token: 'x'.repeat(201) })));
  await assertFails(setDoc(ref, qrCode({ sessionKey: 'tomorrow' })));
  await assertFails(setDoc(ref, qrCode({ generatedAt: new Date() })));
  await assertFails(setDoc(ref, qrCode({ officeName: 'x'.repeat(201) })));
  await assertSucceeds(setDoc(ref, qrCode()));
});

test("a session's code can't be replaced, but the next session's replaces it", async () => {
  const ref = doc(as('sup'), 'attendanceQr', 'o1');
  await assertSucceeds(setDoc(ref, qrCode()));
  await assertFails(
    setDoc(ref, qrCode({ token: 'SAIS-ATT-20261127-AM-ffffffffffffffffffffffffffffffff' })),
  );
  await assertSucceeds(
    setDoc(ref, qrCode({
      token: 'SAIS-ATT-20261127-PM-ffffffffffffffffffffffffffffffff',
      sessionKey: '20261127-PM',
    })),
  );
  await assertFails(deleteDoc(ref));
});

test('the old school-wide code is closed to everyone', async () => {
  for (const uid of ['sup', 'head', 'admin', 'sa']) {
    await assertFails(getDoc(doc(as(uid), 'meta', 'current_qr')));
    await assertFails(
      setDoc(doc(as(uid), 'meta', 'current_qr'), { token: 'X', sessionKey: '20261127-AM' }),
    );
  }
});

// ── attendance recorded by hand ────────────────────────────────────────

const manualRecord = (studentId, over = {}) => ({
  studentName: 'Sia Assistant',
  studentId,
  date: 'Nov 26, 2026',
  timeIn: '8:00 AM',
  timeOut: '11:00 AM',
  totalHours: 3,
  academicYear: '2026-2027',
  officeId: 'o1',
  isInvalid: false,
  isArchived: false,
  editedBy: 'Sam Supervisor',
  editedAt: '2026-11-27T06:00:00.000Z',
  editNote: 'Attendance recorded by hand',
  createdAt: serverTimestamp(),
  ...over,
});

test('a Supervisor records attendance by hand for their own assistant only', async () => {
  await assertSucceeds(
    setDoc(doc(as('sup'), 'attendance', 'sa_20261126_manual_1'), manualRecord('sa')),
  );
  await assertFails(
    setDoc(doc(as('sup2'), 'attendance', 'sa_20261126_manual_2'), manualRecord('sa')),
  );
  await assertFails(
    setDoc(doc(as('sup'), 'attendance', 'stu_20261126_manual_3'), manualRecord('stu')),
  );
  await assertSucceeds(
    setDoc(doc(as('head'), 'attendance', 'sa_20261126_manual_4'), manualRecord('sa')),
  );
});

test("a Supervisor can't record attendance once the assistant's office record is gone", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await deleteDoc(doc(ctx.firestore(), 'officeAssignments', 'sa'));
  });
  await assertFails(
    setDoc(doc(as('sup'), 'attendance', 'sa_20261126_manual_5'), manualRecord('sa')),
  );
});

// ── security hardening checks ───────────────────────────────────────────

test('profile-less verified accounts and deleted accounts cannot access operational data', async () => {
  const noProfile = as('noprofile');
  await assertFails(getDocs(collection(noProfile, 'offices')));
  await assertFails(getDocs(collection(noProfile, 'announcements')));
  await assertFails(
    setDoc(doc(noProfile, 'notifications', 'spam_head'), note('head')),
  );
  // Registration of their own profile still works.
  await assertSucceeds(
    setDoc(
      doc(noProfile, 'users', 'noprofile'),
      newAccount({ email: 'noprofile@example.com' }),
    ),
  );

  // A deleted account marked Active is still blocked.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users', 'del1'), {
      name: 'Deleted User',
      email: 'del1@example.com',
      role: 'Student',
      status: 'Active',
      deleted: true,
    });
  });
  await assertFails(getDocs(collection(as('del1'), 'offices')));
  await assertFails(
    setDoc(doc(as('del1'), 'notifications', 'spam_del'), note('head')),
  );
});

test('a user cannot set requestedRole on their own profile', async () => {
  await assertFails(
    updateDoc(doc(as('stu'), 'users', 'stu'), { requestedRole: 'Head' }),
  );
});

test('notification ids reject URL fragment, query, and whitespace characters', async () => {
  for (const badId of ['n1#x', 'n1?updateMask=x', 'n1 x']) {
    await assertFails(setDoc(doc(as('stu'), 'notifications', badId), note('head')));
  }
  await assertSucceeds(
    setDoc(doc(as('stu'), 'notifications', 'n_1700_head'), note('head')),
  );
  await assertSucceeds(
    setDoc(doc(as('head'), 'notifications', 'clockout_sa_20261127_0'), note('sa')),
  );
});

test('a student assistant can update a task assigned to their legacy roster id', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'students', 'roster_sa'), {
      userId: 'sa',
      name: 'Sia Assistant',
    });
    await setDoc(doc(db, 'tasks', 't_legacy'), {
      assignedTo: 'roster_sa',
      assignedToName: 'Sia Assistant',
      title: 'Sort files',
      status: 'Not Started',
    });
  });
  await assertSucceeds(
    updateDoc(doc(as('sa'), 'tasks', 't_legacy'), { status: 'In Progress' }),
  );
  await assertFails(
    updateDoc(doc(as('stu'), 'tasks', 't_legacy'), { status: 'In Progress' }),
  );
});

test('headForwards create requires author identity, unreviewed status, and office scope', async () => {
  const fwd = (over = {}) => ({
    type: 'report',
    studentId: 'sa',
    studentName: 'Sia Assistant',
    title: 'Week 1',
    fileName: 'w1.pdf',
    sentById: 'sup',
    sentByName: 'Sam Supervisor',
    sentAt: 'Nov 27, 2026',
    reviewed: false,
    ...over,
  });
  await assertSucceeds(setDoc(doc(as('sup'), 'headForwards', 'f1'), fwd()));
  await assertFails(setDoc(doc(as('sup'), 'headForwards', 'f2'), fwd({ sentById: 'sup2' })));
  await assertFails(setDoc(doc(as('sup'), 'headForwards', 'f3'), fwd({ reviewed: true })));
  await assertFails(setDoc(doc(as('sup2'), 'headForwards', 'f4'), fwd({ sentById: 'sup2' })));
  await assertFails(setDoc(doc(as('sup'), 'headForwards', 'f5'), fwd({ studentId: 'stu' })));
});
