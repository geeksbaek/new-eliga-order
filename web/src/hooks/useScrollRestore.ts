import { useEffect, useLayoutEffect, useRef } from 'react'
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

function writeScrollY(key: string, y: number): void {
  try {
    sessionStorage.setItem(key, String(y))
  } catch {
    /* private mode */
  }
}

export type ScrollRestoreOptions = {
  /**
   * When false, stop listening and freeze the last saved Y (cafe list hidden
   * under menu detail). Re-enabling restores that Y before paint.
   */
  enabled?: boolean
  /**
   * Override storage key (pathname+search by default). Cafe list keeps a stable
   * key while the URL is on /menu so chips/scroll survive detail.
   */
  storageKey?: string
}

/**
 * Restore scroll on back/forward; save on unmount / leave.
 *
 * POP / re-enable uses useLayoutEffect so the first paint already has the
 * saved scrollY (avoids sticky chip flash).
 */
export function useScrollRestore(opts?: ScrollRestoreOptions): void {
  const location = useLocation()
  const navType = useNavigationType()
  const enabled = opts?.enabled !== false
  const key =
    PREFIX + (opts?.storageKey ?? `${location.pathname}${location.search}`)
  const wasEnabled = useRef(enabled)
  /** Last Y while this restore target was active (survives detail scroll-to-0). */
  const yRef = useRef(0)

  // Before paint: put the window at the right offset so sticky bars never flash.
  useLayoutEffect(() => {
    if (!enabled) {
      wasEnabled.current = false
      return
    }

    const reactivated = !wasEnabled.current
    wasEnabled.current = true

    if (navType === 'POP' || reactivated) {
      const top = readScrollY(key)
      yRef.current = top
      window.scrollTo({ top, left: 0, behavior: 'instant' as ScrollBehavior })
      return
    }
    yRef.current = 0
    window.scrollTo(0, 0)
  }, [key, navType, enabled])

  // Persist while active. On cleanup write yRef — not window.scrollY — so a
  // sibling layoutEffect that already scrolled to 0 for detail cannot clobber.
  useEffect(() => {
    if (!enabled) return
    yRef.current = window.scrollY
    const save = () => {
      yRef.current = window.scrollY
      writeScrollY(key, yRef.current)
    }
    window.addEventListener('scroll', save, { passive: true })
    return () => {
      window.removeEventListener('scroll', save)
      writeScrollY(key, yRef.current)
    }
  }, [key, enabled])
}
