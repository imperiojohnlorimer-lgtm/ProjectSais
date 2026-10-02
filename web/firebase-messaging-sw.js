// Shows SAIS's push notifications (clock-out reminders) while SAIS is
// closed or in the background. Firebase Messaging registers this exact
// file, from the site root, when the app asks for this browser's token.
//
// Firebase displays each message's notification itself, and a click opens
// the link the clockout-reminders function sets (webpush.fcm_options.link).
// While SAIS is open and showing, messages go to the app instead
// (AppState._listenForPushMessages).
importScripts(
  'https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js',
);

// The web app's settings, as in lib/firebase_options.dart.
firebase.initializeApp({
  apiKey: 'AIzaSyBfr9q5Y0TxDGL4toxlUEZiWaRO7hm8aM0',
  authDomain: 'sais-6168b.firebaseapp.com',
  projectId: 'sais-6168b',
  storageBucket: 'sais-6168b.firebasestorage.app',
  messagingSenderId: '478525793741',
  appId: '1:478525793741:web:4e3d9a6a1013bc6cb01084',
});

firebase.messaging();
