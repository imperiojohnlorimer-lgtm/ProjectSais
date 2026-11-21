// A made-up class schedule in MarSU's grid layout (Time column of 30-minute
// rows, Monday to Saturday, a coloured block per class), as HTML. The
// subjects, instructors and rooms are invented: never put a real student's
// schedule in this repository (it names real people).

export const sampleClasses = [
  { day: 1, start: '8:00', end: '11:00', lines: ['Systems Analysis 1', 'P. Santos', '[Remote]'], colour: '#ffff00', title: 'Systems Analysis 1', mode: 'Online' },
  { day: 1, start: '12:30', end: '3:30', lines: ['Research Project 2', 'L. Reyes', '[Remote]'], colour: '#ffff00', title: 'Research Project 2', mode: 'Online' },
  { day: 2, start: '7:30', end: '10:30', lines: ['Elective 1: Data', 'Mining', 'MT Cruz', '[Remote]'], colour: '#ffff00', title: 'Elective 1: Data Mining', mode: 'Online' },
  { day: 2, start: '11:00', end: '2:00', lines: ['Elective 5: Mobile', 'Development', 'R. Bautista', '[Remote]'], colour: '#ffff00', title: 'Elective 5: Mobile Development', mode: 'Online' },
  { day: 2, start: '3:00', end: '4:30', lines: ['Networking 2', 'G. Villanueva', 'Tech Room'], colour: '#ffff00', title: 'Networking 2', room: 'Tech Room', mode: 'Face-to-Face' },
  { day: 4, start: '7:30', end: '9:30', lines: ['Elective 1: Data', 'Mining', 'MT Cruz', 'CL2'], colour: '#00c000', title: 'Elective 1: Data Mining', room: 'CL2', mode: 'Face-to-Face' },
  { day: 4, start: '10:30', end: '12:00', lines: ['Networking 2', 'G. Villanueva', 'Tech Room'], colour: '#00c000', title: 'Networking 2', room: 'Tech Room', mode: 'Face-to-Face' },
  { day: 4, start: '1:30', end: '3:30', lines: ['Systems Analysis 1', 'P. Santos', 'CL5'], colour: '#00c000', title: 'Systems Analysis 1', room: 'CL5', mode: 'Face-to-Face' },
  { day: 5, start: '1:30', end: '3:30', lines: ['Elective 5: Mobile', 'Development', 'R. Bautista', 'CL4'], colour: '#00c000', title: 'Elective 5: Mobile Development', room: 'CL4', mode: 'Face-to-Face' },
];

/** "1:30" (afternoon when before 7) -> minutes after midnight. */
export function minutes(label) {
  const [h, m] = label.split(':').map(Number);
  return ((h < 7 ? h + 12 : h) % 24) * 60 + m;
}

const ROW = 19; // px per half hour
const FIRST = 7 * 60; // the grid starts at 7:00

export function sampleHtml() {
  const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const rows = 27; // 7:00 to 8:30 PM
  const top = 120;
  const left = 75;
  const timeW = 115;
  const dayW = 115;
  const parts = [];
  parts.push(`<div style="position:absolute;left:${left}px;top:40px;font:bold 22px Arial;text-decoration:underline">BS Information Technology - 4X</div>`);
  // Header row.
  parts.push(`<div class="cell" style="left:${left}px;top:${top - 20}px;width:${timeW}px;height:20px;font-weight:bold">Time</div>`);
  days.forEach((d, i) => {
    parts.push(`<div class="cell" style="left:${left + timeW + i * dayW}px;top:${top - 20}px;width:${dayW}px;height:20px;font-weight:bold">${d}</div>`);
  });
  // Grid rows in the day columns.
  for (let r = 0; r < rows; r++) {
    for (let i = 0; i < days.length; i++) {
      parts.push(`<div class="cell" style="left:${left + timeW + i * dayW}px;top:${top + r * ROW}px;width:${dayW}px;height:${ROW}px"></div>`);
    }
  }
  // The Time column: labels centred on their time, in two staggered columns.
  for (let t = 7 * 60 + 30; t <= 20 * 60; t += 30) {
    const y = top + ((t - FIRST) / 30) * ROW;
    const h = Math.floor(t / 60) % 12 || 12;
    const label = `${h}:${String(t % 60).padStart(2, '0')}`;
    const half = (t / 30) % 2 === 1;
    const x = left + (half ? 0 : timeW / 2);
    parts.push(`<div class="cell" style="left:${x}px;top:${y - ROW}px;width:${timeW / 2}px;height:${ROW * 2}px;line-height:${ROW * 2}px">${label}</div>`);
  }
  for (const c of sampleClasses) {
    const y0 = top + ((minutes(c.start) - FIRST) / 30) * ROW;
    const y1 = top + ((minutes(c.end) - FIRST) / 30) * ROW;
    const x = left + timeW + (c.day - 1) * dayW;
    parts.push(`<div class="block" style="left:${x}px;top:${y0}px;width:${dayW}px;height:${y1 - y0}px;background:${c.colour}"><div>${c.lines.join('<br>')}</div></div>`);
  }
  parts.push(`<div style="position:absolute;left:135px;top:${top + rows * ROW + 20}px;font:italic bold 12px Arial">THIS CLASS SCHEDULE IS SUBJECT TO CHANGE.</div>`);
  return `<!doctype html><html><head><style>
  body { margin:0; background:#fff; width:960px; height:${top + rows * ROW + 60}px; position:relative; font-family:Arial, sans-serif; }
  .cell { position:absolute; box-sizing:border-box; border:1px solid #222; font:12px Arial; text-align:center; }
  .block { position:absolute; box-sizing:border-box; border:1px solid #222; font:11px Arial; display:flex; align-items:center; justify-content:center; text-align:center; }
  </style></head><body>${parts.join('\n')}</body></html>`;
}
