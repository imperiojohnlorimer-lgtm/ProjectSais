// Real-browser check of the class schedule reader (web/schedule-reader/).
//
//   cd tool/schedule_reader_check && npm install && npm run check
//
// Needs Chrome or Edge (set CHROME to its path if it is not in a usual
// place) and an internet connection: the reader downloads Tesseract and
// pdf.js from jsDelivr, as it does in the app. It draws a made-up schedule
// (sample-schedule.mjs), then reads it as
//   - a screenshot (PNG),
//   - a PDF with a text layer (printed by the browser),
//   - a "phone photo" (larger, turned 3 degrees, dimmer, warmer, grainy, JPEG),
// and fails unless every class comes back with the right day, times,
// subject, mode and room. Unit tests of the layout logic are in
// layout.test.cjs (`npm test`, no browser or network needed).
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';
import { sampleClasses, sampleHtml, minutes } from './sample-schedule.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(here, '../../web');

const chromePaths = [
  process.env.CHROME,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
].filter(Boolean);
const chrome = chromePaths.find((p) => fs.existsSync(p));
if (!chrome) throw new Error('No Chrome/Edge found: set CHROME.');

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname === '/test.html') {
    res.writeHead(200, { 'content-type': 'text/html' });
    res.end(`<!doctype html><html><body>
<script src="/schedule-reader/sais-schedule-layout.js"></script>
<script src="/schedule-reader/sais-schedule.js"></script>
</body></html>`);
    return;
  }
  const file = path.join(webRoot, url.pathname);
  if (file.startsWith(webRoot) && fs.existsSync(file) && fs.statSync(file).isFile()) {
    res.writeHead(200, { 'content-type': 'application/javascript' });
    fs.createReadStream(file).pipe(res);
  } else {
    res.writeHead(404).end();
  }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const origin = `http://127.0.0.1:${server.address().port}`;

const browser = await puppeteer.launch({ executablePath: chrome, headless: true });
let failed = 0;
try {
  // The made-up schedule, as a screenshot and as a PDF.
  const draw = await browser.newPage();
  await draw.setViewport({ width: 960, height: 700 });
  await draw.setContent(sampleHtml());
  const height = await draw.evaluate(() => document.body.scrollHeight);
  await draw.setViewport({ width: 960, height });
  const png = await draw.screenshot({ type: 'png' });
  const pdf = await draw.pdf({ width: '960px', height: `${height + 2}px`, printBackground: true });
  await draw.close();

  const page = await browser.newPage();
  page.on('console', (m) => {
    if (m.type() === 'warning' || m.type() === 'error' || process.env.DEBUG) console.log('  [browser]', m.text());
  });
  await page.goto(`${origin}/test.html`);
  if (process.env.DEBUG) await page.evaluate(() => { window.saisScheduleDebug = true; });

  // A phone photo of the screenshot, made in the page.
  const photo = await page.evaluate(async (pngB64) => {
    const bytes = Uint8Array.from(atob(pngB64), (c) => c.charCodeAt(0));
    const bitmap = await createImageBitmap(new Blob([bytes], { type: 'image/png' }));
    const scale = 2.4;
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(bitmap.width * scale * 1.06);
    canvas.height = Math.round(bitmap.height * scale * 1.1);
    const g = canvas.getContext('2d');
    g.fillStyle = '#b9b4a8';
    g.fillRect(0, 0, canvas.width, canvas.height);
    g.translate(canvas.width / 2, canvas.height / 2);
    g.rotate((3 * Math.PI) / 180);
    g.drawImage(bitmap, (-bitmap.width * scale) / 2, (-bitmap.height * scale) / 2, bitmap.width * scale, bitmap.height * scale);
    g.setTransform(1, 0, 0, 1, 0, 0);
    // Dim, warm light that falls off to one side, and grain.
    const data = g.getImageData(0, 0, canvas.width, canvas.height);
    let seed = 11;
    for (let i = 0; i < data.data.length; i += 4) {
      const x = (i / 4) % canvas.width;
      const shade = 0.74 + 0.16 * (x / canvas.width);
      seed = (seed * 1103515245 + 12345) % 2147483648;
      const grain = (seed / 2147483648 - 0.5) * 24;
      data.data[i] = data.data[i] * shade + grain;
      data.data[i + 1] = data.data[i + 1] * shade * 0.97 + grain;
      data.data[i + 2] = data.data[i + 2] * shade * 0.86 + grain;
    }
    g.putImageData(data, 0, 0);
    const blob = await new Promise((r) => canvas.toBlob(r, 'image/jpeg', 0.82));
    const out = new Uint8Array(await blob.arrayBuffer());
    let s = '';
    for (const b of out) s += String.fromCharCode(b);
    return btoa(s);
  }, png.toString('base64'));

  const cases = [
    ['screenshot (PNG)', png.toString('base64'), 'image/png', 'ocr'],
    ['PDF with text', Buffer.from(pdf).toString('base64'), 'application/pdf', 'text'],
    ['phone photo (JPEG)', photo, 'image/jpeg', 'ocr'],
  ];
  const norm = (s) => String(s || '').toLowerCase().replace(/\s+/g, ' ').trim();
  const clock = (m) => (m == null ? '?' : `${Math.floor(m / 60)}:${String(m % 60).padStart(2, '0')}`);
  for (const [name, b64, type, source] of cases.filter((c) => !process.env.CASE || c[0].includes(process.env.CASE))) {
    const started = Date.now();
    const result = await page.evaluate(async (b64, type) => {
      const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
      try {
        return JSON.parse(await window.saisReadSchedule(bytes, type));
      } catch (e) {
        return { error: String(e && e.message) };
      }
    }, b64, type);
    const seconds = ((Date.now() - started) / 1000).toFixed(1);
    if (result.error) {
      console.log(`FAIL ${name}: ${result.error}`);
      failed++;
      continue;
    }
    const problems = [];
    if (result.source !== source) problems.push(`read by ${result.source}, expected ${source}`);
    if (result.meetings.length !== sampleClasses.length) {
      problems.push(`${result.meetings.length} classes found, expected ${sampleClasses.length}`);
    }
    for (const c of sampleClasses) {
      const m = result.meetings.find(
        (x) => x.weekday === c.day && x.start === minutes(c.start) && x.end === minutes(c.end),
      );
      if (!m) {
        problems.push(`missing day ${c.day} ${c.start}-${c.end} ${c.title}`);
        continue;
      }
      // A photo may lose a letter here and there; that's fine as long as
      // the reader marks the class for the student to check.
      const textOk = (same) => same || (name.includes('photo') && m.check);
      if (!textOk(norm(m.title) === norm(c.title))) problems.push(`title "${m.title}" should be "${c.title}"`);
      if (m.mode !== c.mode) problems.push(`${c.title}: mode ${m.mode}`);
      if (!textOk((c.room || '') === (m.room || ''))) problems.push(`${c.title}: room "${m.room}" should be "${c.room || ''}"`);
    }
    if (problems.length) {
      failed++;
      console.log(`FAIL ${name} (${seconds} s):`);
      for (const p of problems) console.log('   -', p);
      for (const m of result.meetings) {
        console.log(`     ${m.weekday} ${clock(m.start)}-${clock(m.end)} ${m.title} | ${m.instructor} | ${m.room} | ${m.mode}${m.check ? ' (check)' : ''}`);
      }
    } else {
      console.log(`ok   ${name} (${seconds} s, ${result.meetings.length} classes)`);
    }
  }
} finally {
  await browser.close();
  server.close();
}
if (failed) {
  console.log(`${failed} failed`);
  process.exit(1);
}
console.log('All schedule reader checks passed.');
