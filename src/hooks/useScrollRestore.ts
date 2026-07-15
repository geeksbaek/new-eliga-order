import { useEffect } from 'react'
import { useLocation, useNavigationType } from 'react-router-dom'

const PREFIX = 'eliga:scroll:'

/**
 * Restore scroll on back/forward; save on unmount / leave.
 */
export function useScrollRestore(): void {
  const location = useLocation()
  const navType = useNavigationType()
  const key = `${PREFIX}${location.pathname}${location.search}`

  useEffect(() => {
    if (navType === 'POP') {
      const raw = sessionStorage.getItem(key)
      const y = raw != null ? Number(raw) : 0
      // wait a frame so cached content can paint first
      requestAnimationFrame(() => {
        window.scrollTo(0, Number.isFinite(y) ? y : 0)
      })
    } else {
      window.scrollTo(0, 0)
    }

    const save = () => {
      sessionStorage.setItem(key, String(window.scrollY))
    }
    window.addEventListener('scroll', save, { passive: true })
    return () => {
      save()
      window.removeEventListener('scroll', save)
    }
  }, [key, navType])
}
