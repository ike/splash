#!/bin/bash

OUTPUT_HTML="${1:-index.html}"
SW_JS="${2:-sw.js}"
OUTPUT_DIR="$(dirname "$OUTPUT_HTML")"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WEATHER_JSON="$SCRIPT_DIR/weather.json"
WATER_JSON="$SCRIPT_DIR/water.json"
SW_JS_PATH="$OUTPUT_DIR/$(basename "$SW_JS")"
MANIFEST_JSON="$OUTPUT_DIR/manifest.json"

# ── write service worker ───────────────────────────────────────────────────────

# Generate a cache-busting version hash from the weather JSON content and webcam image
WEBCAM_IMG="$(dirname "$OUTPUT_HTML")/webcam.jpg"
CACHE_VERSION=$(md5sum "$WEATHER_JSON" "$WATER_JSON" "$WEBCAM_IMG" 2>/dev/null | md5sum | cut -c1-12 || \
                md5 -q "$WEATHER_JSON" "$WATER_JSON" "$WEBCAM_IMG" 2>/dev/null | head -c12)

# Embed the cache version directly into the service worker so the browser
# gets the new cache name as soon as it downloads the updated sw.js file,
# without needing to fetch manifest.json first.
cat > "$SW_JS_PATH" << SWEOF
// Cache version is baked in at build time
const CACHE_NAME = 'weather-v${CACHE_VERSION}';

const ASSETS = [
  './',
  './index.html',
  './webcam.jpg',
  './manifest.json',
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(ASSETS))
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))
      ))
      .then(() => self.clients.claim())
      .then(() => self.clients.matchAll({ type: 'window' }))
      .then(clients => {
        clients.forEach(client => client.navigate(client.url));
      })
  );
});

self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  const isCacheBusted = url.pathname === '/' || url.pathname.endsWith('.html') || url.pathname.endsWith('.json') || url.pathname.endsWith('.jpg');

  if (isCacheBusted) {
    event.respondWith(
      caches.match(event.request).then(cached => {
        if (cached) return cached;
        return fetch(event.request).then(response =>
          caches.open(CACHE_NAME).then(cache => {
            cache.put(event.request, response.clone());
            return response;
          })
        );
      })
    );
    return;
  }

  event.respondWith(
    caches.match(event.request).then(cached => cached || fetch(event.request))
  );
});

self.addEventListener('message', event => {
  if (event.data?.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
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
  "theme_color": "#eeeeee"
}
MANIFESTEOF

echo "Generated: $SW_JS_PATH (cache version: weather-v${CACHE_VERSION})"
echo "Generated: $MANIFEST_JSON"
