// Kill-switch service worker.
//
// The old Flutter web build registered a service worker at this exact path
// (/flutter_service_worker.js) that cache-firsts the whole app shell. After the
// Next.js wedge replaced Flutter on onemind.life, returning visitors kept being
// served the STALE cached Flutter site by that still-registered SW (its own
// asset files now 404, so per spec the browser keeps the old SW instead of
// updating — it can never self-heal).
//
// Shipping a *different* script at the same URL forces the browser's periodic SW
// update check (which fires on navigation, independent of the cache-first fetch
// handler) to install THIS script instead. It then clears every cache,
// unregisters itself, and reloads controlled tabs so they fetch the fresh wedge
// from the network. One-time self-destruct; the wedge ships no SW of its own.
self.addEventListener('install', function () {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    (async function () {
      try {
        var keys = await caches.keys();
        await Promise.all(keys.map(function (k) { return caches.delete(k); }));
      } catch (e) { /* best effort */ }
      try {
        await self.registration.unregister();
      } catch (e) { /* best effort */ }
      var clients = await self.clients.matchAll({ type: 'window' });
      clients.forEach(function (client) {
        try { client.navigate(client.url); } catch (e) { /* ignore */ }
      });
    })()
  );
});

// While briefly in control, never serve from cache — always go to network.
self.addEventListener('fetch', function (event) {
  event.respondWith(
    fetch(event.request).catch(function () {
      return new Response('', { status: 503, statusText: 'Service Unavailable' });
    })
  );
});
