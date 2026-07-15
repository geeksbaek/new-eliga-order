import { useEffect, useLayoutEffect } from 'react'
import { useLocation, useNavigationType } from 'react-router-dom'

const PREFIX = 'eliga:scroll:'

function readScrollY(key: string): number {
  try {
    const raw = sessionStorage.getItem(key)
    if (raw == null) return 0
    const y = Number(raw)
    return Number.isFinite(y) ? y : 0
  } catch {
    return 0
  }
}

/**
 * Restore scroll on back/forward; save on unmount / leave.
 *
 * POP uses useLayoutEffect so the first paint already has the saved scrollY.
 * (Deferred rAF restore left sticky shop/category chips unstuck for 1–2 frames.)
 */
export function useScrollRestore(): void {
  const location = useLocation()
  const navType = useNavigationType()
  const key = `${PREFIX}${location.pathname}${location.search}`

  // Before paint: put the window at the right offset so sticky bars never flash.
  useLayoutEffect(() => {
    if (navType === 'POP') {
      const top = readScrollY(key)
      window.scrollTo({ top, left: 0, behavior: 'instant' as ScrollBehavior })
      // One more pass after children commit (list height from cache).
      const id = requestAnimationFrame(() => {
        window.scrollTo({ top, left: 0, behavior: 'instant' as ScrollBehavior })
      })
      return () => cancelAnimationFrame(id)
    }
    window.scrollTo(0, 0)
  }, [key, navType])

  // Persist while the user scrolls; flush on leave.
  useEffect(() => {
    const save = () => {
      try {
        sessionStorage.setItem(key, String(window.scrollY))
      } catch {
        /* private mode */
      }
    }
    window.addEventListener('scroll', save, { passive: true })
    return () => {
      save()
      window.removeEventListener('scroll', save)
    }
  }, [key, navType])
}
