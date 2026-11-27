// Run with: node --test sw.test.cjs
//
// The caching rules of web/sais-sw.js. The file exports them when loaded
// outside a service worker.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const sw = require('../../web/sais-sw.js');

const ORIGIN = 'https://sais-6168b.web.app';

test("SAIS's own files: network first", () => {
  for (const path of ['/', '/main.dart.js', '/attendance', '/assets/FontManifest.json',
    '/vendor/zxing/zxing-library-0.21.3.min.js', '/favicon.png?v=2']) {
    assert.equal(sw.cachePolicy(ORIGIN + path, ORIGIN, 'GET', false), 'network-first', path);
  }
});

test('versioned Google files: stored copy first', () => {
  const urls = [
    'https://www.gstatic.com/flutter-canvaskit/052f31d1/chromium/canvaskit.wasm',
    `https://www.gstatic.com/firebasejs/${sw.FIREBASE_JS_VERSION}/firebase-app.js`,
    'https://fonts.gstatic.com/s/roboto/v32/KFOmCnqEu92Fr1Me5WZLCzYlKw.ttf',
  ];
  for (const url of urls) assert.equal(sw.cachePolicy(url, ORIGIN, 'GET', false), 'cache-first', url);
});

test('data and everything else are never touched', () => {
  const urls = [
    'https://firestore.googleapis.com/google.firestore.v1.Firestore/Listen/channel',
    'https://identitytoolkit.googleapis.com/v1/accounts:lookup',
    'https://securetoken.googleapis.com/v1/token',
    'https://hksswjhioztqsypbrkjy.supabase.co/functions/v1/clock-attendance',
    'https://cdn.jsdelivr.net/npm/tesseract.js@7.0.0/dist/tesseract.min.js',
    'https://www.gstatic.com/recaptcha/api.js',
    `${ORIGIN}/__/auth/handler`,
    `${ORIGIN}/sais-sw.js`,
    `${ORIGIN}/firebase-messaging-sw.js`,
    'not a url',
  ];
  for (const url of urls) assert.equal(sw.cachePolicy(url, ORIGIN, 'GET', false), 'none', url);
});

test('only plain GETs', () => {
  assert.equal(sw.cachePolicy(`${ORIGIN}/main.dart.js`, ORIGIN, 'POST', false), 'none');
  assert.equal(sw.cachePolicy(`${ORIGIN}/main.dart.js`, ORIGIN, 'GET', true), 'none');
});

test('page addresses are the app; files are not', () => {
  assert.equal(sw.isAppPage(`${ORIGIN}/`, ORIGIN, true), true);
  assert.equal(sw.isAppPage(`${ORIGIN}/academic-year/2026-2027`, ORIGIN, true), true);
  assert.equal(sw.isAppPage(`${ORIGIN}/main.dart.js`, ORIGIN, true), false);
  assert.equal(sw.isAppPage(`${ORIGIN}/attendance`, ORIGIN, false), false);
  assert.equal(sw.isAppPage('https://example.com/x', ORIGIN, true), false);
});

test('old CanvasKit and Firebase versions are cleared', () => {
  const rev = 'aaa111';
  const v = sw.FIREBASE_JS_VERSION;
  assert.equal(sw.isOutdated(`https://www.gstatic.com/flutter-canvaskit/bbb222/canvaskit.js`, rev, v), true);
  assert.equal(sw.isOutdated(`https://www.gstatic.com/flutter-canvaskit/${rev}/canvaskit.js`, rev, v), false);
  assert.equal(sw.isOutdated('https://www.gstatic.com/firebasejs/11.0.0/firebase-app.js', rev, v), true);
  assert.equal(sw.isOutdated(`https://www.gstatic.com/firebasejs/${v}/firebase-app.js`, rev, v), false);
  // Unknown revision: keep CanvasKit rather than guess.
  assert.equal(sw.isOutdated('https://www.gstatic.com/flutter-canvaskit/bbb222/canvaskit.js', null, v), false);
  assert.equal(sw.isOutdated(`${ORIGIN}/main.dart.js`, rev, v), false);
});

test('the engine revision is read from flutter_bootstrap.js', () => {
  const bootstrap = '_flutter.buildConfig = {"engineRevision":"052f31d115eceda8cbff1b3481fcde4330c4ae12","builds":[]};';
  assert.equal(sw.engineRevisionIn(bootstrap), '052f31d115eceda8cbff1b3481fcde4330c4ae12');
  assert.equal(sw.engineRevisionIn('nothing here'), null);
});
