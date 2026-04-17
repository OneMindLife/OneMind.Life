importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

// Fill in your Firebase Web config. Generate via `flutterfire configure`
// or copy from your Firebase Console → Project Settings → Your apps (Web).
firebase.initializeApp({
  apiKey: 'YOUR_API_KEY',
  appId: 'YOUR_APP_ID',
  messagingSenderId: 'YOUR_SENDER_ID',
  projectId: 'YOUR_PROJECT_ID',
  authDomain: 'YOUR_PROJECT_ID.firebaseapp.com',
  storageBucket: 'YOUR_PROJECT_ID.firebasestorage.app',
  measurementId: 'YOUR_MEASUREMENT_ID',
});

const messaging = firebase.messaging();

// Handle background messages (app not in foreground)
messaging.onBackgroundMessage(function(payload) {
  var data = payload.data || {};
  var title = data.title || 'OneMind';
  var body = data.body || 'A phase has changed';
  var chatId = data.chat_id;

  return self.registration.showNotification(title, {
    body: body,
    icon: '/icons/Icon-192.png',
    data: { chat_id: chatId, url: '/?chat_id=' + chatId },
  });
});

// Handle notification click — open or focus the app
self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  var url = event.notification.data && event.notification.data.url ? event.notification.data.url : '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(windowClients) {
      for (var i = 0; i < windowClients.length; i++) {
        if (windowClients[i].url.indexOf(self.location.origin) !== -1) {
          windowClients[i].focus();
          windowClients[i].navigate(url);
          return;
        }
      }
      return clients.openWindow(url);
    })
  );
});
