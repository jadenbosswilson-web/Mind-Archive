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

// ---------------- Calendar reminders (real Web Push) ----------------
// Fired when the send-reminders Edge Function (see README) sends a push
// message via the Web Push protocol — this runs even if the app/tab is
// closed, as long as the browser process can wake the service worker.
// The payload is plain JSON set by that function: { title, body, url }.
self.addEventListener('push', (event) => {
  let data = {};
  try{ data = event.data ? event.data.json() : {}; }catch(err){ data = { title: 'Reminder', body: event.data ? event.data.text() : '' }; }
  const title = data.title || "Sainha's Pages reminder";
  const options = {
    body: data.body || '',
    icon: '/icon-192.png',
    badge: '/icon-192.png',
    tag: data.tag || 'calendar-reminder',
    data: { url: data.url || '/' }
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

// Clicking the notification focuses an already-open tab if there is one,
// otherwise opens a new one — landing on the calendar (or wherever the
// reminder's url points, e.g. a specific ?e=<token> event link).
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetUrl = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil((async () => {
    const allClients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for(const client of allClients){
      if('focus' in client){
        client.focus();
        if('navigate' in client) client.navigate(targetUrl).catch(()=>{});
        return;
      }
    }
    if(self.clients.openWindow) self.clients.openWindow(targetUrl);
  })());
});
