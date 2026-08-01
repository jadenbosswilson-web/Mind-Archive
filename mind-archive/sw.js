// Minimal service worker — its main job is just to exist and have a
// fetch handler, since that's part of what Chrome and other browsers
// check before offering a real "Install app" (standalone) experience
// instead of a plain browser bookmark. It doesn't do any caching of its
// own; every request just goes straight to the network as normal.
self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  event.respondWith(fetch(event.request));
});
