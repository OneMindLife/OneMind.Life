importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'YOUR_FIREBASE_API_KEY',
  appId: 'YOUR_FIREBASE_APP_ID',
  messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
  projectId: 'YOUR_FIREBASE_PROJECT_ID',
  authDomain: 'YOUR_FIREBASE_PROJECT_ID.firebaseapp.com',
  storageBucket: 'YOUR_FIREBASE_PROJECT_ID.firebasestorage.app',
  measurementId: 'G-2XCF0J8BGQ',
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
    // Must be /home: '/' is the marketing LandingScreen and ignores chat_id,
    // so a tapped notification would land on the hero page instead of the chat.
    data: { chat_id: chatId, url: '/home?chat_id=' + chatId },
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
