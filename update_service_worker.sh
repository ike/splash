#!/bin/bash

OUTPUT_HTML="${OUTPUT_HTML:-index.html}"
SW_JS="${SW_JS:-sw.js}"

# ── write service worker ───────────────────────────────────────────────────────

# Generate a cache-busting version hash from the weather JSON content and webcam image
WEBCAM_IMG="$(dirname "$OUTPUT_HTML")/webcam.jpg"
CACHE_VERSION=$(md5sum "$WEATHER_JSON" "$WATER_JSON" "$WEBCAM_IMG" 2>/dev/null | md5sum | cut -c1-12 || \
                md5 -q "$WEATHER_JSON" "$WATER_JSON" "$WEBCAM_IMG" 2>/dev/null | head -c12)

SW_JS="$(dirname "$OUTPUT_HTML")/sw.js"
cat > "$SW_JS" << SWEOF
const CACHE_NAME = 'weather-v${CACHE_VERSION}';
const ASSETS = [
  './',
  './index.html',
  './webcam.jpg',
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', event => {
  // Stale-while-revalidate: serve from cache immediately, update cache in background
  event.respondWith(
    caches.open(CACHE_NAME).then(async cache => {
      const cached = await cache.match(event.request);

      const networkFetch = fetch(event.request).then(response => {
        if (response && response.status === 200 && response.type !== 'opaque') {
          // Only update cache if the response has actually changed
          cache.match(event.request).then(existing => {
            if (!existing) {
              cache.put(event.request, response.clone());
            } else {
              // Compare via cloned text to detect changes
              Promise.all([existing.clone().text(), response.clone().text()]).then(([oldBody, newBody]) => {
                if (oldBody !== newBody) {
                  cache.put(event.request, response.clone());
                  // Notify all clients that fresh content is available
                  self.clients.matchAll().then(clients =>
                    clients.forEach(client => client.postMessage({ type: 'CACHE_UPDATED', url: event.request.url }))
                  );
                }
              });
            }
          });
        }
        return response;
      }).catch(() => null);

      // Return cached response immediately if available, otherwise wait for network
      return cached || networkFetch;
    })
  );
});
SWEOF

echo "Generated: $SW_JS"
