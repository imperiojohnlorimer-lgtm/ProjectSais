/* SAIS offline cache.
 *
 * Keeps SAIS's own files, Flutter's CanvasKit, Firebase's scripts and the
 * fonts on the device, so SAIS still opens with no signal and doesn't hang
 * on a weak one. It never touches data: Firestore, Firebase Auth, Supabase
 * and every other request go to the network as before.
 *
 * - SAIS's own files: network first (the browser still revalidates them, so
 *   a new deploy shows as soon as there is signal), the stored copy when the
 *   network fails or takes longer than NETWORK_TIMEOUT_MS. Every page
 *   address is the single-page app, so it is answered with the stored "/".
 * - CanvasKit, Firebase's scripts and Google's fonts are versioned and never
 *   change: stored copy first.
 *
 * Firebase's script version must match firebase_core_web's
 * (test/offline_cache_test.dart checks it). Change CACHE_VERSION when this
 * file's caching changes.
 */
'use strict';

const CACHE_VERSION = 'sais-offline-v1';
const FIREBASE_JS_VERSION = '12.19.0';
const NETWORK_TIMEOUT_MS = 4000;

// Loaded by Firebase.initializeApp on every start (firebase_core_web).
const FIREBASE_SCRIPTS = [
  'firebase-app.js',
  'firebase-auth.js',
  'firebase-firestore-pipelines.js',
  'firebase-messaging.js',
];

// Stored when the worker installs, so SAIS opens offline from the first
// visit. Relative to the worker's scope.
const CORE_FILES = [
  './',
  'flutter_bootstrap.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png?v=2',
  'icons/Icon-192.png?v=2',
  'icons/Icon-512.png?v=2',
  'icons/Icon-maskable-192.png?v=2',
  'icons/Icon-maskable-512.png?v=2',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
  'vendor/zxing/zxing-library-0.21.3.min.js',
];

// Never handled here: the push worker, this worker, and Firebase Hosting's
// reserved paths.
const SKIPPED_PATHS = ['/sais-sw.js', '/firebase-messaging-sw.js'];

/**
 * How a request is answered: 'network-first', 'cache-first', or 'none'
 * (left to the browser). [origin] is SAIS's own origin.
 */
function cachePolicy(url, origin, method, hasRange) {
  if (method !== 'GET' || hasRange) return 'none';
  let parsed;
  try {
    parsed = new URL(url);
  } catch (_) {
    return 'none';
  }
  if (parsed.origin === origin) {
    if (parsed.pathname.startsWith('/__/')) return 'none';
    if (SKIPPED_PATHS.includes(parsed.pathname)) return 'none';
    return 'network-first';
  }
  if (parsed.origin === 'https://www.gstatic.com') {
    if (parsed.pathname.startsWith('/flutter-canvaskit/')) return 'cache-first';
    if (parsed.pathname.startsWith('/firebasejs/')) return 'cache-first';
    return 'none';
  }
  if (parsed.origin === 'https://fonts.gstatic.com') return 'cache-first';
  return 'none';
}

/**
 * Whether [url] holds a CanvasKit or Firebase script version other than the
 * current ones, so it can be deleted.
 */
function isOutdated(url, engineRevision, firebaseVersion) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch (_) {
    return false;
  }
  if (parsed.origin !== 'https://www.gstatic.com') return false;
  const parts = parsed.pathname.split('/');
  if (parts[1] === 'flutter-canvaskit') {
    return engineRevision !== null && parts[2] !== engineRevision;
  }
  if (parts[1] === 'firebasejs') return parts[2] !== firebaseVersion;
  return false;
}

/** Whether a page address (not a file) is asked for. */
function isAppPage(url, origin, isNavigation) {
  if (!isNavigation) return false;
  const parsed = new URL(url);
  if (parsed.origin !== origin) return false;
  const last = parsed.pathname.split('/').pop();
  return !last.includes('.');
}

/** The engine revision in flutter_bootstrap.js's build config, or null. */
function engineRevisionIn(bootstrap) {
  const match = /"engineRevision"\s*:\s*"([0-9a-f]+)"/.exec(bootstrap || '');
  return match ? match[1] : null;
}

if (typeof module !== 'undefined') {
  // For tool/offline_check (node), which tests the rules above.
  module.exports = {
    cachePolicy,
    isOutdated,
    isAppPage,
    engineRevisionIn,
    FIREBASE_JS_VERSION,
    FIREBASE_SCRIPTS,
  };
} else {
  const scope = self.registration.scope;
  const origin = self.location.origin;
  const indexUrl = new URL('./', scope).href;

  // The three files one start of SAIS needs together; an install that
  // couldn't store them fails, so the previous worker and cache stay.
  const ESSENTIAL = ['./', 'flutter_bootstrap.js', 'main.dart.js'].map(
    (file) => new URL(file, scope).href,
  );

  const storable = (response) =>
    response &&
    response.status === 200 &&
    !response.redirected &&
    (response.type === 'basic' || response.type === 'cors');

  // Never lets a full or cleared storage break a download that worked.
  async function store(cache, key, response) {
    if (!storable(response)) return;
    try {
      await cache.put(key, response.clone());
    } catch (_) {}
  }

  // Best effort: one file that can't be fetched doesn't stop the rest.
  async function storeAll(cache, urls) {
    await Promise.all(
      urls.map(async (url) => {
        try {
          const response = await fetch(url, { credentials: 'same-origin' });
          await store(cache, url, response);
        } catch (_) {}
      }),
    );
  }

  async function currentEngineRevision(cache) {
    const bootstrap = await cache.match(new URL('flutter_bootstrap.js', scope).href);
    return bootstrap ? engineRevisionIn(await bootstrap.text()) : null;
  }

  self.addEventListener('install', (event) => {
    event.waitUntil(
      (async () => {
        const cache = await caches.open(CACHE_VERSION);
        await storeAll(cache, CORE_FILES.map((file) => new URL(file, scope).href));
        for (const url of ESSENTIAL) {
          if (!(await cache.match(url))) {
            throw new Error('SAIS offline cache: could not store ' + url);
          }
        }
        // CanvasKit comes through the page's list after its first frame
        // (below): which build the browser uses can't be told from here.
        await storeAll(
          cache,
          FIREBASE_SCRIPTS.map(
            (file) => 'https://www.gstatic.com/firebasejs/' + FIREBASE_JS_VERSION + '/' + file,
          ),
        );
        try {
          const manifest = await cache.match(new URL('assets/FontManifest.json', scope).href);
          const fonts = manifest ? await manifest.json() : [];
          const files = fonts.flatMap((family) =>
            (family.fonts || []).map((font) => new URL('assets/' + font.asset, scope).href),
          );
          await storeAll(cache, files);
        } catch (_) {}
        await self.skipWaiting();
      })(),
    );
  });

  self.addEventListener('activate', (event) => {
    event.waitUntil(
      (async () => {
        for (const name of await caches.keys()) {
          if (name.startsWith('sais-offline-') && name !== CACHE_VERSION) {
            await caches.delete(name);
          }
        }
        const cache = await caches.open(CACHE_VERSION);
        const revision = await currentEngineRevision(cache);
        for (const request of await cache.keys()) {
          if (isOutdated(request.url, revision, FIREBASE_JS_VERSION)) {
            await cache.delete(request);
          }
        }
        await self.clients.claim();
      })(),
    );
  });

  // The page lists what its first load fetched (before this worker was in
  // charge, and the CanvasKit build it chose), so those files are stored.
  self.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.type !== 'sais-store' || !Array.isArray(data.urls)) return;
    const urls = data.urls
      .filter((url) => typeof url === 'string')
      .filter((url) => cachePolicy(url, origin, 'GET', false) !== 'none')
      .slice(0, 300);
    event.waitUntil(
      (async () => {
        const cache = await caches.open(CACHE_VERSION);
        const missing = [];
        for (const url of urls) {
          if (!(await cache.match(url))) missing.push(url);
        }
        await storeAll(cache, missing);
      })(),
    );
  });

  // One start of SAIS takes its files from one place: the page address
  // decides, and its page's later requests follow. Otherwise a weak signal
  // could mix a new flutter_bootstrap.js with an old main.dart.js. Kept in
  // memory: if the worker restarts mid-start, the file-by-file rule below
  // still applies.
  const pageSource = new Map(); // client id -> 'network' | 'cache'

  function remember(clientId, source) {
    if (!clientId) return;
    pageSource.set(clientId, source);
    if (pageSource.size > 50) pageSource.delete(pageSource.keys().next().value);
  }

  async function cacheFirst(event, key) {
    const cache = await caches.open(CACHE_VERSION);
    const stored = await cache.match(key);
    if (stored) return stored;
    const response = await fetch(event.request);
    event.waitUntil(store(cache, key, response));
    return response;
  }

  // The network, unless it fails, or (when [waitForNetwork] is false) takes
  // longer than NETWORK_TIMEOUT_MS to answer while a stored copy exists.
  // The copy is refreshed in the background either way. Gives the response
  // and where it came from.
  async function networkFirst(event, key, waitForNetwork) {
    const cache = await caches.open(CACHE_VERSION);
    const network = fetch(event.request).then((response) => {
      event.waitUntil(store(cache, key, response));
      return response;
    });
    event.waitUntil(network.catch(() => {}));
    const stored = await cache.match(key);
    if (!stored) return { response: await network, source: 'network' };
    // A server error (Hosting having a bad moment) is no better than no
    // answer: the stored copy serves instead.
    if (waitForNetwork) {
      try {
        const response = await network;
        if (response.status < 500) return { response, source: 'network' };
      } catch (_) {}
      return { response: stored, source: 'cache' };
    }
    const timeout = new Promise((resolve) =>
      setTimeout(() => resolve(null), NETWORK_TIMEOUT_MS),
    );
    try {
      const first = await Promise.race([network, timeout]);
      if (first && first.status < 500) {
        return { response: first, source: 'network' };
      }
    } catch (_) {}
    return { response: stored, source: 'cache' };
  }

  self.addEventListener('fetch', (event) => {
    const request = event.request;
    const policy = cachePolicy(
      request.url,
      origin,
      request.method,
      request.headers.has('range'),
    );
    if (policy === 'none') return;
    if (policy === 'cache-first') {
      event.respondWith(cacheFirst(event, request));
      return;
    }
    if (isAppPage(request.url, origin, request.mode === 'navigate')) {
      event.respondWith(
        networkFirst(event, indexUrl, false).then(({ response, source }) => {
          remember(event.resultingClientId, source);
          return response;
        }),
      );
      return;
    }
    const source = pageSource.get(event.clientId);
    if (source === 'cache') {
      // The page came from the cache, so its files do too (the network
      // only for one never stored).
      event.respondWith(cacheFirst(event, request));
      return;
    }
    // The page came from the network: its files wait for the network too
    // (the stored copy only if it fails).
    event.respondWith(
      networkFirst(event, request, source === 'network').then(
        ({ response }) => response,
      ),
    );
  });
}
