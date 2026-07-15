import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import './index.css'

const basename = import.meta.env.BASE_URL.replace(/\/$/, '') || '/'

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
  window.addEventListener('load', () => {
    const swUrl = `${basename === '/' ? '' : basename}/sw.js`
    void navigator.serviceWorker
      .register(swUrl, { scope: basename === '/' ? '/' : `${basename}/` })
      .then((reg) => {
        // Pick up new SW without leaving a stale controller forever
        reg.update().catch(() => {})
        if (reg.waiting) reg.waiting.postMessage({ type: 'SKIP_WAITING' })
        reg.addEventListener('updatefound', () => {
          const sw = reg.installing
          if (!sw) return
          sw.addEventListener('statechange', () => {
            if (sw.state === 'installed' && navigator.serviceWorker.controller) {
              // New version ready — soft claim on next load via skipWaiting in SW
            }
          })
        })
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
