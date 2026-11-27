{{flutter_js}}
{{flutter_build_config}}

// No serviceWorkerSettings: Flutter's own service worker is a stub that
// unregisters itself, and asking for it would replace SAIS's offline cache
// (sais-sw.js, registered from index.html).
_flutter.loader.load();
