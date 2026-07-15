/* new-eliga service worker — installability + meal notifications */
/* eslint-disable no-restricted-globals */

const CACHE = 'new-eliga-shell-v1'

/** App shell assets to precache (paths relative to origin). */
const PRECACHE = ['/', '/manifest.webmanifest', '/favicon.svg', '/icon-192.png']

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.addAll(PRECACHE).catch(() => undefined))
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

self.addEventListener('fetch', (event) => {
  const req = event.request
  if (req.method !== 'GET') return

  let url
  try {
    url = new URL(req.url)
  } catch {
    return
  }
  // Same-origin only
  if (url.origin !== self.location.origin) return
  // Never cache API / auth
  if (isApi(url)) return

  // SPA navigations: network first, fall back to cached shell
  if (isNavigation(req)) {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone()
          if (res.ok) {
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

  // Static assets: stale-while-revalidate
  if (
    url.pathname.startsWith('/assets/') ||
    url.pathname.endsWith('.js') ||
    url.pathname.endsWith('.css') ||
    url.pathname.endsWith('.png') ||
    url.pathname.endsWith('.svg') ||
    url.pathname.endsWith('.webmanifest') ||
    url.pathname.endsWith('.woff2')
  ) {
    event.respondWith(
      caches.open(CACHE).then(async (cache) => {
        const cached = await cache.match(req)
        const network = fetch(req)
          .then((res) => {
            if (res && res.ok) void cache.put(req, res.clone())
            return res
          })
          .catch(() => cached)
        return cached || network
      }),
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
    typeof data.title === 'string' ? data.title.slice(0, 120) : '엘리가'
  const options =
    data.options && typeof data.options === 'object' ? { ...data.options } : {}
  if (typeof options.body === 'string') options.body = options.body.slice(0, 400)
  if (options.data && typeof options.data.url === 'string') {
    options.data = { ...options.data, url: safeNavUrl(options.data.url) }
  }
  event.waitUntil(self.registration.showNotification(title, options))
})
