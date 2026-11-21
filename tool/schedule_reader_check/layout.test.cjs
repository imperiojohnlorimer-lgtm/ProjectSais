// Unit tests of the schedule reader's layout logic
// (web/schedule-reader/sais-schedule-layout.js). No browser, no network:
//   cd tool/schedule_reader_check && npm test
const test = require('node:test');
const assert = require('node:assert/strict');
const L = require('../../web/schedule-reader/sais-schedule-layout.js');

/** A white picture with filled rectangles {x0, y0, x1, y1, rgb}. */
function picture(width, height, rects) {
  const pixels = new Uint8ClampedArray(width * height * 4).fill(255);
  for (const r of rects) {
    for (let y = r.y0; y < r.y1; y++) {
      for (let x = r.x0; x < r.x1; x++) {
        const p = (y * width + x) * 4;
        pixels[p] = r.rgb[0];
        pixels[p + 1] = r.rgb[1];
        pixels[p + 2] = r.rgb[2];
      }
    }
  }
  return { width, height, pixels };
}

const YELLOW = [255, 255, 0];
const GREEN = [0, 192, 0];
const word = (text, x0, y0, x1, y1, conf = 95) => ({ text, x0, y0, x1, y1, conf });

test('reads clock labels, including misreads', () => {
  assert.deepEqual(L.parseClock('7:30'), { h: 7, m: 30 });
  assert.deepEqual(L.parseClock('12.00'), { h: 12, m: 0 });
  assert.deepEqual(L.parseClock('1000'), { h: 10, m: 0 });
  assert.deepEqual(L.parseClock('l:3O'), { h: 1, m: 30 });
  assert.equal(L.parseClock('7:45'), null);
  assert.equal(L.parseClock('THIS'), null);
  assert.equal(L.parseClock('13:00'), null);
});

test('labels run from morning into the afternoon and evening', () => {
  const labels = ['7:30', '8:00', '11:30', '12:00', '12:30', '1:00', '5:00', '7:30', '8:00'].map(
    (t, i) => ({ ...L.parseClock(t), y: 100 + i * 20 }),
  );
  const out = L.labelMinutes(labels.slice(0, 7));
  assert.deepEqual(out.map((p) => p.minutes), [450, 480, 690, 720, 750, 780, 1020]);
  const evening = L.labelMinutes([
    { h: 6, m: 0, y: 10 },
    { h: 6, m: 30, y: 20 },
    { h: 7, m: 0, y: 30 },
  ]);
  assert.deepEqual(evening.map((p) => p.minutes), [1080, 1110, 1140]);
});

test('fits the time scale and ignores a misread label', () => {
  const words = [];
  for (let t = 450; t <= 1200; t += 30) {
    const h = Math.floor(t / 60) % 12 || 12;
    const text = `${h}:${String(t % 60).padStart(2, '0')}`;
    const y = 135 + ((t - 450) / 30) * 18.6;
    words.push(word(text, 90, y - 5, 115, y + 5));
  }
  words[5].text = '9:00'; // really 10:00, out of line
  const scale = L.fitTimeScale(words);
  assert.ok(scale);
  assert.equal(L.minutesAt(154, scale), 480); // 8:00
  assert.equal(L.minutesAt(265, scale), 660); // 11:00
  assert.equal(L.fitTimeScale([word('7:30', 0, 0, 1, 1)]), null);
});

test('finds day columns, filling in a missed day', () => {
  assert.equal(L.dayIndex('Monday'), 0);
  assert.equal(L.dayIndex('Wednesda;'), 2);
  assert.equal(L.dayIndex('Thur'), 3);
  assert.equal(L.dayIndex('Seminar'), -1);
  const days = L.dayCentres([
    word('Monday', 214, 88, 282, 126),
    word('Tuesday', 335, 88, 402, 126),
    word('Thursday', 562, 88, 633, 126),
    word('Saturday', 790, 88, 861, 126),
  ]);
  assert.ok(days);
  assert.ok(Math.abs(days.centres[2] - 483) < 8);
  assert.ok(Math.abs(days.centres[4] - 711) < 8);
  assert.equal(L.dayAt(250, days), 0);
  assert.equal(L.dayAt(100, days), -1);
});

test('a day word read across two columns does not shift the others', () => {
  const days = L.dayCentres([
    word('Tuesday', 577, 90, 848, 110), // "Monday Tuesday", read as one
    word('Wednesday', 734, 90, 848, 110),
    word('Thursday', 934, 90, 1019, 110),
    word('Friday', 1130, 90, 1186, 110),
    word('Saturday', 1300, 90, 1379, 110),
  ]);
  assert.equal(L.dayAt(612, days), 1);
  assert.equal(L.dayAt(430, days), 0);
});

test('finds coloured blocks and splits back-to-back ones', () => {
  const image = picture(400, 300, [
    { x0: 100, y0: 40, x1: 180, y1: 120, rgb: YELLOW },
    // Two green classes, one dark line between them.
    { x0: 200, y0: 40, x1: 280, y1: 100, rgb: GREEN },
    { x0: 200, y0: 100, x1: 280, y1: 101, rgb: [20, 20, 20] },
    { x0: 200, y0: 101, x1: 280, y1: 160, rgb: GREEN },
    // Too small to be a class.
    { x0: 10, y0: 10, x1: 14, y1: 14, rgb: YELLOW },
  ]);
  const blocks = L.findBlocks(image);
  assert.equal(blocks.length, 3);
  assert.deepEqual(
    blocks.map((b) => [b.x0, b.y0, b.x1, b.y1]),
    [[100, 40, 180, 120], [200, 40, 280, 100], [200, 101, 280, 160]],
  );
  assert.equal(L.estimateTilt(image, blocks), 0);
});

test('measures a tilt from the blocks', () => {
  const width = 400;
  const height = 300;
  const image = picture(width, height, []);
  // A block whose edges drop 1 px every 20 px to the right.
  for (let x = 100; x < 200; x++) {
    const drop = Math.floor((x - 100) / 20);
    for (let y = 50 + drop; y < 150 + drop; y++) {
      const p = (y * width + x) * 4;
      image.pixels.set(YELLOW, p);
    }
  }
  const tilt = L.estimateTilt(image, L.findBlocks(image));
  assert.ok(Math.abs(tilt - 0.05) < 0.01, `tilt ${tilt}`);
});

test('splits a block into subject, instructor, room and mode', () => {
  const lines = (...t) => t.map((text) => ({ text, conf: 90 }));
  assert.deepEqual(
    L.parseBlockText(lines('Elective 3: Artificial', 'Intelligence', 'RC Perez', '[Remote]')),
    { title: 'Elective 3: Artificial Intelligence', instructor: 'RC Perez', room: '', mode: 'Online', conf: 90 },
  );
  assert.deepEqual(
    L.parseBlockText(lines('Software Eng. 2', 'J. Mercado', 'CLS')),
    { title: 'Software Eng. 2', instructor: 'J. Mercado', room: 'CL5', mode: 'Face-to-Face', conf: 90 },
  );
  assert.equal(L.parseBlockText(lines('Elective 2: IT', 'Seminar', 'E. De Leon-Cruz', 'Tech Room')).room, 'Tech Room');
  assert.equal(L.parseBlockText(lines('PE 3')).title, 'PE 3');
  assert.equal(L.parseBlockText([]).title, '');
});

test('room numbers misread as letters are put right', () => {
  assert.equal(L.fixRoom('CLS'), 'CL5');
  assert.equal(L.fixRoom('Rm l2'), 'Rm 12');
  assert.equal(L.fixRoom('Tech Room'), 'Tech Room');
  assert.equal(L.fixRoom('CLASS'), 'CLASS');
});

test('groups words into lines', () => {
  const lines = L.toLines([
    word('Intelligence', 10, 30, 80, 42),
    word('Elective', 10, 10, 50, 22),
    word('3:', 55, 11, 65, 22),
  ]);
  assert.deepEqual(lines.map((l) => l.text), ['Elective 3:', 'Intelligence']);
});

test('reads a whole schedule with given words', async () => {
  // Header at y 88-126, rows of 18.6 px from 7:30 at y 135.5, two classes.
  const image = picture(960, 680, [
    { x0: 190, y0: 154, x1: 312, y1: 265, rgb: YELLOW }, // Monday 8:00-11:00
    { x0: 542, y0: 359, x1: 656, y1: 432, rgb: GREEN }, // Thursday 1:30-3:30
  ]);
  const header = [
    word('Time', 69, 88, 120, 126),
    word('Monday', 214, 88, 282, 126),
    word('Tuesday', 335, 88, 402, 126),
    word('Wednesday', 442, 88, 525, 126),
    word('Thursday', 562, 88, 633, 126),
    word('Friday', 683, 88, 738, 126),
    word('Saturday', 790, 88, 861, 126),
  ];
  const times = [];
  for (let t = 450; t <= 1200; t += 30) {
    const h = Math.floor(t / 60) % 12 || 12;
    const y = 135.5 + ((t - 450) / 30) * 18.6;
    times.push(word(`${h}:${String(t % 60).padStart(2, '0')}`, 90, y - 5, 115, y + 5));
  }
  const blockWords = [
    word('Systems', 200, 180, 250, 190), word('Analysis', 255, 180, 300, 190),
    word('P.', 230, 200, 240, 210), word('Santos', 245, 200, 290, 210),
    word('[Remote]', 225, 220, 280, 230),
    word('Systems', 550, 370, 590, 380), word('Analysis', 595, 370, 640, 380),
    word('P.', 570, 390, 580, 400), word('Santos', 585, 390, 630, 400),
    word('CL5', 585, 410, 610, 420),
  ];
  const all = [...header, ...times, ...blockWords];
  const result = await L.readSchedule(image, async (_, rect) =>
    all.filter((w) => {
      const cx = (w.x0 + w.x1) / 2;
      const cy = (w.y0 + w.y1) / 2;
      return cx >= rect.x0 && cx <= rect.x1 && cy >= rect.y0 && cy <= rect.y1;
    }),
  );
  assert.equal(result.ok, true);
  assert.deepEqual(result.warnings, []);
  assert.deepEqual(
    result.meetings.map((m) => [m.weekday, m.start, m.end, m.title, m.instructor, m.room, m.mode, m.check]),
    [
      [1, 480, 660, 'Systems Analysis', 'P. Santos', '', 'Online', false],
      [4, 810, 930, 'Systems Analysis', 'P. Santos', 'CL5', 'Face-to-Face', false],
    ],
  );
});

test('a picture with no blocks says so', async () => {
  const result = await L.readSchedule(picture(200, 100, []), async () => []);
  assert.equal(result.ok, false);
  assert.equal(result.meetings.length, 0);
});

test('without readable times the classes are kept, marked to check', async () => {
  const image = picture(400, 300, [{ x0: 100, y0: 100, x1: 180, y1: 200, rgb: YELLOW }]);
  const result = await L.readSchedule(image, async (_, rect) =>
    rect.y0 >= 98 ? [word('Math', 110, 140, 150, 150)] : [],
  );
  assert.equal(result.meetings.length, 1);
  assert.equal(result.meetings[0].start, null);
  assert.equal(result.meetings[0].check, true);
  assert.ok(result.warnings.length >= 1);
});

test('coloured header cells are not taken for classes', async () => {
  const MAROON = [128, 0, 0];
  // A maroon "Monday" header cell above a yellow class.
  const image = picture(960, 680, [
    { x0: 190, y0: 88, x1: 312, y1: 126, rgb: MAROON },
    { x0: 190, y0: 154, x1: 312, y1: 265, rgb: YELLOW },
  ]);
  const header = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'].map(
    (d, i) => word(d, 214 + i * 115, 95, 282 + i * 115, 120),
  );
  const times = [];
  for (let t = 450; t <= 1200; t += 30) {
    const h = Math.floor(t / 60) % 12 || 12;
    const y = 135.5 + ((t - 450) / 30) * 18.6;
    times.push(word(`${h}:${String(t % 60).padStart(2, '0')}`, 90, y - 5, 115, y + 5));
  }
  const all = [...header, ...times, word('Statistics', 210, 200, 290, 210)];
  const result = await L.readSchedule(image, async (_, rect) =>
    all.filter((w) => {
      const cx = (w.x0 + w.x1) / 2;
      const cy = (w.y0 + w.y1) / 2;
      return cx >= rect.x0 && cx <= rect.x1 && cy >= rect.y0 && cy <= rect.y1;
    }),
  );
  assert.deepEqual(result.meetings.map((m) => [m.title, m.weekday, m.start, m.end]), [
    ['Statistics', 1, 480, 660],
  ]);
});

test('light print on a dark cell is turned dark on light for reading', () => {
  const image = picture(40, 20, [
    { x0: 0, y0: 0, x1: 40, y1: 20, rgb: [128, 0, 0] },
    { x0: 10, y0: 8, x1: 30, y1: 12, rgb: [255, 255, 255] },
  ]);
  const crop = L.cropForOcr(image, { x0: 0, y0: 0, x1: 40, y1: 20 }, { plain: true });
  const at = (x, y) => crop.pixels[(y * crop.width + x) * 4];
  assert.ok(at(2, 2) > 200, 'the cell becomes light');
  assert.ok(at(20, 10) < 60, 'the print becomes dark');
});
