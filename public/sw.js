// VFarmers Service Worker
// Strategy:
//   - App shell (HTML, JS, CSS, fonts, images) → Cache-first with network fallback
//   - Supabase API / live data requests → Network-only (never cached)
//   - Navigation requests → Serve cached shell when offline

const CACHE_VERSION = "vfarmers-v1";
const SHELL_CACHE = `${CACHE_VERSION}-shell`;

// URLs that should NEVER be served from cache (live data)
const LIVE_HOSTS = [
  "supabase.co",
  "supabase.in",
];

function isLiveRequest(url) {
  return LIVE_HOSTS.some((h) => url.hostname.includes(h));
}

function isNavigationRequest(request) {
  return request.mode === "navigate";
}

function isStaticAsset(url) {
  return (
    url.pathname.startsWith("/_app/") ||
    url.pathname.startsWith("/avatars/") ||
    url.pathname.startsWith("/icons/") ||
    /\.(js|css|woff2?|png|svg|ico|webp|jpg|jpeg|gif)$/.test(url.pathname)
  );
}

// ── Install: pre-cache the app shell ────────────────────────────────────────
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(SHELL_CACHE)
      .then((cache) =>
        cache.addAll([
          "/",
          "/manifest.json",
          "/favicon.ico",
        ]),
      )
      .then(() => self.skipWaiting()),
  );
});

// ── Activate: clear old caches ───────────────────────────────────────────────
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((k) => k.startsWith("vfarmers-") && k !== SHELL_CACHE)
            .map((k) => caches.delete(k)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

// ── Fetch: routing strategy ──────────────────────────────────────────────────
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // 1. Live/API requests — always network-only, never cache
  if (isLiveRequest(url)) {
    event.respondWith(fetch(event.request));
    return;
  }

  // 2. Static assets — cache-first, fallback to network then cache
  if (isStaticAsset(url)) {
    event.respondWith(
      caches.open(SHELL_CACHE).then(async (cache) => {
        const cached = await cache.match(event.request);
        if (cached) return cached;
        try {
          const response = await fetch(event.request);
          if (response.ok) cache.put(event.request, response.clone());
          return response;
        } catch {
          return new Response("Offline", { status: 503 });
        }
      }),
    );
    return;
  }

  // 3. Navigation (page loads) — network-first, fall back to cached shell
  if (isNavigationRequest(event.request)) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          // Cache successful page responses
          if (response.ok) {
            caches
              .open(SHELL_CACHE)
              .then((cache) => cache.put(event.request, response.clone()));
          }
          return response;
        })
        .catch(async () => {
          // Offline: serve cached version of the same URL or fall back to "/"
          const cache = await caches.open(SHELL_CACHE);
          return (
            (await cache.match(event.request)) ||
            (await cache.match("/")) ||
            new Response("Offline", { status: 503 })
          );
        }),
    );
    return;
  }

  // 4. Everything else — network with cache fallback
  event.respondWith(
    fetch(event.request).catch(async () => {
      const cache = await caches.open(SHELL_CACHE);
      return (await cache.match(event.request)) || new Response("Offline", { status: 503 });
    }),
  );
});
