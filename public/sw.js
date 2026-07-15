/* 엘리가오더 service worker — installability + meal notifications */
/* eslint-disable no-restricted-globals */

/**
 * Bump CACHE whenever shell strategy changes so activate drops old entries.
 * Hashed /assets/* files are cache-friendly; navigations stay network-first.
 */
const CACHE = 'eliga-order-shell-v3'

/** App shell assets to precache (paths relative to origin). */
const PRECACHE = [
  '/',
  '/manifest.webmanifest',
  '/favicon.svg',
  '/icon-192.png',
  '/icon-512.png',
  '/apple-touch-icon.png',
]

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.addAll(PRECACHE).catch(() => undefined))
      // Activate as soon as installed so clients can claim on next message/reload
      .then(() => self.skipWaiting()),
  )
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))),
      )
      .then(() => self.clients.claim()),
  )
})

function isApi(url) {
  return url.pathname.startsWith('/api/')
}

function isNavigation(req) {
  return req.mode === 'navigate' || req.destination === 'document'
}

/** Hashed build output — safe to cache long-term. */
function isBuildAsset(url) {
  return url.pathname.startsWith('/assets/')
}

/** Icons / manifest / root sw — prefer network when online. */
function isShellAsset(url) {
  const p = url.pathname
  return (
    p === '/sw.js' ||
    p.endsWith('.webmanifest') ||
    p.endsWith('.png') ||
    p.endsWith('.svg') ||
    p.endsWith('.ico') ||
    p.endsWith('.woff2')
  )
}

self.addEventListener('fetch', (event) => {
  const req = event.request
  if (req.method !== 'GET') return

  let url
  try {
    url = new URL(req.url)
  } catch {
    return
  }
  if (url.origin !== self.location.origin) return
  if (isApi(url)) return

  // SPA document: always try network first so deploys show up on next open
  if (isNavigation(req)) {
    event.respondWith(
      fetch(req)
        .then((res) => {
          if (res.ok) {
            const copy = res.clone()
            void caches.open(CACHE).then((c) => c.put('/', copy))
          }
          return res
        })
        .catch(() =>
          caches.match('/').then((hit) => hit || caches.match(req)),
        ),
    )
    return
  }

  // Never let an old sw.js stick forever offline-first
  if (url.pathname === '/sw.js') {
    event.respondWith(
      fetch(req, { cache: 'no-store' }).catch(() => caches.match(req)),
    )
    return
  }

  // Vite hashed bundles: cache-first (URL changes every deploy)
  if (isBuildAsset(url)) {
    event.respondWith(
      caches.open(CACHE).then(async (cache) => {
        const cached = await cache.match(req)
        if (cached) return cached
        const res = await fetch(req)
        if (res && res.ok) void cache.put(req, res.clone())
        return res
      }),
    )
    return
  }

  // Icons / fonts / manifest: network-first so rebrand/icons update
  if (isShellAsset(url)) {
    event.respondWith(
      fetch(req)
        .then((res) => {
          if (res && res.ok) {
            void caches.open(CACHE).then((c) => c.put(req, res.clone()))
          }
          return res
        })
        .catch(() => caches.match(req)),
    )
  }
})

/** Only same-origin relative paths — block open redirects via notification data. */
function safeNavUrl(raw) {
  if (typeof raw !== 'string' || !raw) return '/'
  const t = raw.trim()
  if (!t) return '/'
  if (t.startsWith('/') && !t.startsWith('//')) {
    if (t.includes('\\') || t.includes('://')) return '/'
    return t
  }
  try {
    const u = new URL(t, self.location.origin)
    if (u.origin !== self.location.origin) return '/'
    return `${u.pathname}${u.search}${u.hash}` || '/'
  } catch {
    return '/'
  }
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const raw = event.notification.data && event.notification.data.url
  const target = safeNavUrl(raw)
  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        for (const client of clientList) {
          if ('focus' in client) {
            client.focus()
            if ('navigate' in client && typeof client.navigate === 'function') {
              return client.navigate(target)
            }
            return undefined
          }
        }
        if (self.clients.openWindow) {
          return self.clients.openWindow(target)
        }
        return undefined
      }),
  )
})

self.addEventListener('message', (event) => {
  const data = event.data
  if (!data || typeof data !== 'object') return
  if (data.type === 'SKIP_WAITING') {
    void self.skipWaiting()
    return
  }
  if (data.type !== 'SHOW_NOTIFICATION') return
  const title =
    typeof data.title === 'string' ? data.title.slice(0, 120) : '엘리가오더'
  const options =
    data.options && typeof data.options === 'object' ? { ...data.options } : {}
  if (typeof options.body === 'string') options.body = options.body.slice(0, 400)
  if (options.data && typeof options.data.url === 'string') {
    options.data = { ...options.data, url: safeNavUrl(options.data.url) }
  }
  event.waitUntil(self.registration.showNotification(title, options))
})
