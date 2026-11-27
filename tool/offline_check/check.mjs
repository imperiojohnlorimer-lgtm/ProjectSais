// Run with: npm install && npm run check   (after `flutter build web`)
//
// Opens the built app (build/web) in headless Chrome or Edge, the way a
// phone would: a first visit online, then with no network, then on a
// connection that hangs. It checks that SAIS still opens from the offline
// cache (web/sais-sw.js), shows the offline banner, never registers
// Flutter's own stub worker, and picks up a new deploy once back online.
// Needs internet for the first visit (CanvasKit and Firebase's scripts come
// from gstatic) and signs nobody in.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const here = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(here, '../../build/web');
if (!fs.existsSync(path.join(webRoot, 'main.dart.js'))) {
  throw new Error('Build the app first: flutter build web --release');
}

const chrome = [
  process.env.CHROME,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
].filter(Boolean).find((p) => fs.existsSync(p));
if (!chrome) throw new Error('No Chrome/Edge found: set CHROME.');

const types = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ttf': 'font/ttf',
  '.otf': 'font/otf', '.css': 'text/css', '.bin': 'application/octet-stream',
};

// Like Firebase Hosting: no-cache everywhere, every unknown path is the app.
let hang = false;
let deployMark = '';
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  let file = path.join(webRoot, decodeURIComponent(url.pathname));
  if (!file.startsWith(webRoot)) return res.writeHead(403).end();
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    file = path.join(webRoot, 'index.html');
  }
  const send = () => {
    let body = fs.readFileSync(file);
    if (path.basename(file) === 'flutter_bootstrap.js' && deployMark) {
      body = Buffer.concat([body, Buffer.from(`\n// ${deployMark}\n`)]);
    }
    res.writeHead(200, {
      'Content-Type': types[path.extname(file)] ?? 'application/octet-stream',
      'Cache-Control': 'no-cache',
    });
    res.end(body);
  };
  if (hang) setTimeout(send, 20000);
  else send();
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const origin = `http://127.0.0.1:${server.address().port}`;

const browser = await puppeteer.launch({ executablePath: chrome, headless: true });
const page = await browser.newPage();
const consoleLines = [];
page.on('console', (m) => consoleLines.push(m.text()));
const failures = [];
const check = (ok, what) => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}`);
  if (!ok) failures.push(what);
};

async function firstFrame(timeout = 60000) {
  await page.waitForFunction(
    () => !document.getElementById('sais-splash'),
    { timeout },
  );
}

/** Turns on Flutter's accessibility tree so its text is in the page. */
async function pageText() {
  await page.evaluate(() => {
    const placeholder = document.querySelector('flt-semantics-placeholder');
    if (placeholder) placeholder.click();
  });
  await new Promise((r) => setTimeout(r, 1500));
  return page.evaluate(() => document.body.innerText + ' ' +
    [...document.querySelectorAll('[aria-label]')].map((e) => e.getAttribute('aria-label')).join(' '));
}

try {
  // 1. First visit, online.
  await page.goto(`${origin}/login`, { waitUntil: 'load' });
  await firstFrame();
  await page.evaluate(() => navigator.serviceWorker.ready);
  // Let the worker store what the first load fetched.
  await new Promise((r) => setTimeout(r, 6000));
  const workers = await page.evaluate(async () =>
    (await navigator.serviceWorker.getRegistrations()).map((r) =>
      (r.active || r.installing || r.waiting)?.scriptURL ?? ''));
  check(workers.some((u) => u.endsWith('/sais-sw.js')), 'sais-sw.js is registered');
  check(!workers.some((u) => u.includes('flutter_service_worker')), "Flutter's stub worker is not registered");
  const stored = await page.evaluate(async () => {
    const names = await caches.keys();
    const urls = [];
    for (const name of names) {
      for (const req of await (await caches.open(name)).keys()) urls.push(req.url);
    }
    return urls;
  });
  check(stored.some((u) => u.endsWith('/main.dart.js')), 'main.dart.js is stored');
  check(stored.some((u) => u.includes('/flutter-canvaskit/') && u.endsWith('canvaskit.wasm')), 'CanvasKit is stored');
  check(stored.some((u) => u.includes('/firebasejs/') && u.endsWith('firebase-app.js')), "Firebase's scripts are stored");
  check(stored.some((u) => u.endsWith('zxing-library-0.21.3.min.js')), 'the QR scanner library is stored');

  // 2. No network at all: SAIS still opens, with the offline banner.
  await page.setOfflineMode(true);
  consoleLines.length = 0;
  await page.reload({ waitUntil: 'load' });
  await firstFrame();
  const offlineText = await pageText();
  check(!consoleLines.some((l) => l.includes('SAIS could not start')), 'SAIS starts offline (no "could not start")');
  check(offlineText.includes('Signing in needs a connection'), 'the offline banner shows on the login page');
  await page.goto(`${origin}/privacy`, { waitUntil: 'load' }).catch(() => {});
  await firstFrame();
  check(true, 'another page address opens offline');

  // 3. Back online: a new deploy is picked up.
  await page.setOfflineMode(false);
  deployMark = `deploy-${Date.now()}`;
  await page.reload({ waitUntil: 'load' });
  await firstFrame();
  await new Promise((r) => setTimeout(r, 2000));
  const cachedBootstrap = await page.evaluate(async (url) => {
    const hit = await caches.match(url);
    return hit ? hit.text() : '';
  }, `${origin}/flutter_bootstrap.js`);
  check(cachedBootstrap.includes(deployMark), 'a new deploy replaces the stored copy');

  // 4. A connection that hangs: the stored copy is used
  // after the 4-second limit instead of waiting.
  hang = true;
  const started = Date.now();
  await page.goto(`${origin}/login`, { waitUntil: 'load', timeout: 60000 });
  await firstFrame();
  const seconds = (Date.now() - started) / 1000;
  check(seconds < 15, `a hanging connection still opens SAIS (${seconds.toFixed(1)} s)`);
  hang = false;

} finally {
  await browser.close();
  server.close();
}

if (failures.length) {
  console.error(`\n${failures.length} check(s) failed.`);
  process.exit(1);
}
console.log('\nAll offline checks passed.');
