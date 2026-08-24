// Firebase Cloud Messaging service worker for the wedge (web push).
//
// The ENTIRE server pipeline already exists and runs in prod: the
// `notify_push_round` DB trigger fires on every round phase flip →
// `push-events` edge fn → `_shared/fcm.ts` fans out a data-only FCM message to
// every active participant's web token in `fcm_tokens`. This SW is the missing
// client half: it renders those background messages and routes a tap into the
// chat.
//
// FCM project is `onemind-bfba5` (sender 772415659270) — the SAME project whose
// service account the sender uses. It is INDEPENDENT of where these files are
// hosted (onemind-95fb2). Config is copied verbatim from the Flutter app's
// web/firebase-messaging-sw.js; only the click-through URL and icon differ
// (Flutter routed to /home?chat_id=, the wedge routes to /g/<code>).
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAdxcfvFN10TYeVGEmLzwhz1GSYfJqRmXA',
  appId: '1:772415659270:web:d7e397a8fd8d5af7dfd287',
  messagingSenderId: '772415659270',
  projectId: 'onemind-bfba5',
  authDomain: 'onemind-bfba5.firebaseapp.com',
  storageBucket: 'onemind-bfba5.firebasestorage.app',
  measurementId: 'G-2XCF0J8BGQ',
});

const messaging = firebase.messaging();

// Background messages (tab closed / not focused) — this is the whole point:
// bring the away user back when a round opens or a winner is picked.
messaging.onBackgroundMessage(function (payload) {
  var data = payload.data || {};
  var title = data.title || 'OneMind';
  var body = data.body || 'A new round is open';
  // Route straight into the chat surface. The sender includes the invite code;
  // fall back to GLOBAL (the world chat) if an older payload lacks it.
  var code = data.code || 'GLOBAL';
  return self.registration.showNotification(title, {
    body: body,
    icon: '/icon-192.png',
    badge: '/icon-192.png',
    tag: 'onemind-round-' + code, // collapse repeats for the same chat
    data: { url: '/g/' + code },
  });
});

// Tap → focus an existing OneMind tab and navigate it, else open a new one.
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var url =
    (event.notification.data && event.notification.data.url) || '/g/GLOBAL';
  event.waitUntil(
    clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then(function (windowClients) {
        for (var i = 0; i < windowClients.length; i++) {
          var c = windowClients[i];
          if (c.url.indexOf(self.location.origin) !== -1) {
            c.focus();
            c.navigate(url);
            return;
          }
        }
        return clients.openWindow(url);
      }),
  );
});
