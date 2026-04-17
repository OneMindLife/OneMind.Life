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
