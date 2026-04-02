#!/bin/bash

OUTPUT_HTML="${1:-index.html}"
SW_JS="${2:-sw.js}"
OUTPUT_DIR="$(dirname "$OUTPUT_HTML")"
WEATHER_JSON="./weather.json"
WATER_JSON="./water.json"
SW_JS_PATH="$OUTPUT_DIR/$(basename "$SW_JS")"
MANIFEST_JSON="$OUTPUT_DIR/manifest.json"

# ── write service worker ───────────────────────────────────────────────────────

# Generate a cache-busting version hash from the weather JSON content and webcam image
WEBCAM_IMG="$(dirname "$OUTPUT_HTML")/webcam.jpg"
CACHE_VERSION=$(md5sum "$WEATHER_JSON" "$WATER_JSON" "$WEBCAM_IMG" 2>/dev/null | md5sum | cut -c1-12 || \
                md5 -q "$WEATHER_JSON" "$WATER_JSON" "$WEBCAM_IMG" 2>/dev/null | head -c12)

cat > "$SW_JS_PATH" << SWEOF
// Cache name is read from the manifest at runtime
const ASSETS = [
  './',
  './index.html',
  './webcam.jpg',
  './manifest.json',
];

async function getCacheName() {
  const resp = await fetch('./manifest.json');
  const manifest = await resp.json();
  return manifest.cache_name || 'weather-v1';
}

self.addEventListener('install', event => {
  event.waitUntil(
    getCacheName().then(CACHE_NAME =>
      caches.open(CACHE_NAME).then(cache => cache.addAll(ASSETS))
    )
  );
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    getCacheName().then(CACHE_NAME =>
      caches.keys().then(keys =>
        Promise.all(
          keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))
        )
      )
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', event => {
  // Stale-while-revalidate: serve from cache immediately, update cache in background
  event.respondWith(
    caches.match(event.request).then(cached => {
      // Serve cached version immediately (super fast load)
      // In the background, check if manifest cache_name changed and invalidate if so
      const networkUpdate = getCacheName().then(CACHE_NAME =>
        caches.open(CACHE_NAME).then(async cache => {
          try {
            const response = await fetch(event.request);
            if (response && response.status === 200 && response.type !== 'opaque') {
              // Check if this response differs from what's cached
              const existing = await cache.match(event.request);
              if (!existing) {
                cache.put(event.request, response.clone());
              } else {
                const [oldBody, newBody] = await Promise.all([
                  existing.clone().text(),
                  response.clone().text()
                ]);
                if (oldBody !== newBody) {
                  cache.put(event.request, response.clone());
                  // Notify clients that content changed so they can reload
                  const clients = await self.clients.matchAll();
                  clients.forEach(client => client.postMessage({ type: 'CACHE_UPDATED', url: event.request.url }));
                }
              }
            }
            return response;
          } catch {
            return null;
          }
        })
      );

      // Serve from cache immediately; fall back to network if not cached
      return cached || networkUpdate;
    })
  );
});
SWEOF

# ── write web app manifest ─────────────────────────────────────────────────────

cat > "$MANIFEST_JSON" << MANIFESTEOF
{
  "name": "Weather",
  "short_name": "Weather",
  "start_url": "./",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#eeeeee",
  "cache_name": "weather-v${CACHE_VERSION}"
}
MANIFESTEOF

echo "Generated: $SW_JS_PATH"
echo "Generated: $MANIFEST_JSON"
