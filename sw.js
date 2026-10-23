// P² Sales Vertriebs MultiTool – Offline-Speicher
const APP = 'p2gk-app-v5';
const TILES = 'p2gk-tiles-v1';
const IMG = 'p2gk-img-v1'; // Kundenbilder: ändern sich nie, daher aus dem Speicher
const MAX_TILES = 4000;
const SHELL = ['./', './index.html', './manifest.webmanifest', './icon.svg'];
const LIBS = [
  'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css',
  'https://cdn.jsdelivr.net/npm/leaflet-rotate@0.2.8/dist/leaflet-rotate.js',
  'https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.117.2/dist/umd/supabase.js'
];
const TILE_HOSTS = ['tile.openstreetmap.org', 'server.arcgisonline.com', 'www.wms.nrw.de'];

self.addEventListener('install', e => {
  e.waitUntil((async () => {
    const c = await caches.open(APP);
    await c.addAll(SHELL);
    await Promise.all(LIBS.map(u => fetch(u, { mode: 'cors' }).then(r => r.ok && c.put(u, r)).catch(() => {})));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k !== APP && k !== TILES && k !== IMG) await caches.delete(k);
    await self.clients.claim();
  })());
});

let puts = 0;
async function trimTiles() {
  const c = await caches.open(TILES);
  const keys = await c.keys();
  for (let i = 0; i < keys.length - MAX_TILES; i++) await c.delete(keys[i]);
}

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Kundenbilder: einmal laden, danach aus dem Speicher (spart mobile Daten)
  if (url.origin === self.location.origin && url.pathname.includes('/assets/customers/')) {
    e.respondWith(caches.open(IMG).then(async c => (await c.match(req)) || fetch(req).then(res => { if (res.ok) c.put(req, res.clone()); return res; })));
    return;
  }

  // App selbst: erst Netz (Updates kommen sofort an), offline aus dem Speicher
  if (url.origin === self.location.origin) {
    e.respondWith((async () => {
      try {
        const res = await fetch(req, { cache: 'no-cache' });
        if (res.ok) (await caches.open(APP)).put(req, res.clone());
        return res;
      } catch (err) {
        return (await caches.match(req, { ignoreSearch: true })) || (req.mode === 'navigate' ? caches.match('./index.html') : Response.error());
      }
    })());
    return;
  }

  // Bibliotheken: aus dem Speicher
  if (LIBS.includes(req.url)) {
    e.respondWith(caches.match(req.url).then(r => r || fetch(req).then(res => {
      if (res.ok) caches.open(APP).then(c => c.put(req.url, res.clone()));
      return res;
    })));
    return;
  }

  // Kartenkacheln: bis 14 Tage aus dem Speicher, sonst Netz; offline immer aus dem Speicher
  if (TILE_HOSTS.includes(url.hostname)) {
    e.respondWith((async () => {
      const c = await caches.open(TILES);
      const hit = await c.match(req);
      const age = hit ? Date.now() - Date.parse(hit.headers.get('date') || 0) : Infinity;
      if (hit && age < 14 * 864e5) return hit;
      try {
        const res = await fetch(req);
        if (res.ok) { c.put(req, res.clone()); if (++puts % 100 === 0) trimTiles(); }
        return res;
      } catch (err) {
        return hit || Response.error();
      }
    })());
  }
});
