import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import { isStandaloneDisplay, subscribeStandaloneDisplay } from './lib/display-mode'
import { applyTextSize } from './lib/text-size'
import './index.css'

// Restore text size before first paint of React tree
applyTextSize()

const basename = import.meta.env.BASE_URL.replace(/\/$/, '') || '/'

/**
 * Mark installed web app so CSS can disable native overscroll only there.
 * (iOS home-screen may not match display-mode media queries alone.)
 */
function syncStandaloneClass() {
  const on = isStandaloneDisplay()
  document.documentElement.classList.toggle('is-standalone', on)
  document.body.classList.toggle('is-standalone', on)
}
syncStandaloneClass()
subscribeStandaloneDisplay(() => syncStandaloneClass())

/** App-like: block pinch-zoom / ctrl+wheel zoom where the browser allows. */
function lockViewportZoom() {
  const block = (e: Event) => {
    e.preventDefault()
  }
  // iOS Safari legacy gesture events
  document.addEventListener('gesturestart', block, { passive: false })
  document.addEventListener('gesturechange', block, { passive: false })
  document.addEventListener('gestureend', block, { passive: false })
  // Desktop / Android browser zoom via ctrl/cmd + wheel
  document.addEventListener(
    'wheel',
    (e) => {
      if (e.ctrlKey || e.metaKey) e.preventDefault()
    },
    { passive: false },
  )
  // Multi-touch pinch on some browsers
  let lastTouchCount = 0
  document.addEventListener(
    'touchmove',
    (e) => {
      if (e.touches.length > 1) {
        e.preventDefault()
        lastTouchCount = e.touches.length
      } else if (lastTouchCount > 1) {
        lastTouchCount = 0
      }
    },
    { passive: false },
  )
}

lockViewportZoom()

function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) return

  // One full reload when a new SW takes control (after skipWaiting + claim)
  let refreshing = false
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (refreshing) return
    refreshing = true
    window.location.reload()
  })

  const promptWaiting = (reg: ServiceWorkerRegistration) => {
    const w = reg.waiting
    if (w) w.postMessage({ type: 'SKIP_WAITING' })
  }

  window.addEventListener('load', () => {
    const swUrl = `${basename === '/' ? '' : basename}/sw.js`
    void navigator.serviceWorker
      .register(swUrl, { scope: basename === '/' ? '/' : `${basename}/` })
      .then((reg) => {
        // Already a waiting worker from a previous visit
        promptWaiting(reg)
        void reg.update().catch(() => {})

        reg.addEventListener('updatefound', () => {
          const sw = reg.installing
          if (!sw) return
          sw.addEventListener('statechange', () => {
            // New SW installed while an old one still controls the page
            if (sw.state === 'installed' && navigator.serviceWorker.controller) {
              promptWaiting(reg)
            }
          })
        })

        // Standalone PWA often stays open for hours — re-check on focus
        const onVisible = () => {
          if (document.visibilityState === 'visible') {
            void reg.update().catch(() => {})
            promptWaiting(reg)
          }
        }
        document.addEventListener('visibilitychange', onVisible)
        window.addEventListener('focus', onVisible)
      })
      .catch(() => {
        /* optional — page Notification still works without SW */
      })
  })
}

registerServiceWorker()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter basename={basename === '/' ? undefined : basename}>
      <App />
    </BrowserRouter>
  </StrictMode>,
)
