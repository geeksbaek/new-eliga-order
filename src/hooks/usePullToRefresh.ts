import { useEffect, useRef, useState } from 'react'
import { useStandaloneDisplay } from './useStandaloneDisplay'

const PULL_RESISTANCE = 0.42
const PULL_MAX = 112
const PULL_THRESHOLD = 64
/** Start tracking only when already at (near) top of document. */
const TOP_SLOP = 2

export type PullToRefreshState = {
  /** Visual pull distance (px), 0 when idle */
  pull: number
  /** Past threshold — release will refresh */
  armed: boolean
  /** Refresh promise in flight */
  refreshing: boolean
}

type Options = {
  onRefresh: () => void | Promise<void>
  /** Extra gate (e.g. disable on login). Default true when standalone. */
  enabled?: boolean
}

/**
 * Custom pull-to-refresh for installed PWA only.
 * Mobile Chrome tabs keep the browser's native PTR — we never attach there.
 */
export function usePullToRefresh({
  onRefresh,
  enabled = true,
}: Options): PullToRefreshState {
  const standalone = useStandaloneDisplay()
  const active = standalone && enabled

  const [pull, setPull] = useState(0)
  const [refreshing, setRefreshing] = useState(false)

  const onRefreshRef = useRef(onRefresh)
  onRefreshRef.current = onRefresh

  const pullRef = useRef(0)
  const trackingRef = useRef(false)
  const startYRef = useRef(0)
  const startXRef = useRef(0)
  const decidedRef = useRef(false)
  const horizontalRef = useRef(false)
  const refreshingRef = useRef(false)

  useEffect(() => {
    if (!active) {
      pullRef.current = 0
      setPull(0)
      return
    }

    const atTop = () =>
      (window.scrollY || document.documentElement.scrollTop || 0) <= TOP_SLOP

    const locked = () => document.body.classList.contains('is-scroll-lock')

    const setPullBoth = (v: number) => {
      pullRef.current = v
      setPull(v)
    }

    const onTouchStart = (e: TouchEvent) => {
      if (refreshingRef.current || locked()) return
      if (e.touches.length !== 1) return
      if (!atTop()) return
      trackingRef.current = true
      decidedRef.current = false
      horizontalRef.current = false
      startYRef.current = e.touches[0].clientY
      startXRef.current = e.touches[0].clientX
    }

    const onTouchMove = (e: TouchEvent) => {
      if (!trackingRef.current || refreshingRef.current) return
      if (e.touches.length !== 1) {
        trackingRef.current = false
        setPullBoth(0)
        return
      }
      if (locked()) {
        trackingRef.current = false
        setPullBoth(0)
        return
      }

      const y = e.touches[0].clientY
      const x = e.touches[0].clientX
      const dy = y - startYRef.current
      const dx = x - startXRef.current

      if (!decidedRef.current) {
        if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return
        decidedRef.current = true
        // Horizontal swipe (chip strips, rails) — never steal
        if (Math.abs(dx) > Math.abs(dy)) {
          horizontalRef.current = true
          trackingRef.current = false
          setPullBoth(0)
          return
        }
        // Finger going up or not at top anymore
        if (dy <= 0 || !atTop()) {
          trackingRef.current = false
          setPullBoth(0)
          return
        }
      }

      if (horizontalRef.current) return
      if (dy <= 0) {
        setPullBoth(0)
        return
      }
      if (!atTop() && pullRef.current === 0) {
        trackingRef.current = false
        return
      }

      // Own the gesture so the page doesn't scroll while we show rubber-band
      if (e.cancelable) e.preventDefault()
      const next = Math.min(dy * PULL_RESISTANCE, PULL_MAX)
      setPullBoth(next)
    }

    const finish = async () => {
      if (!trackingRef.current && pullRef.current === 0) return
      trackingRef.current = false
      const shouldRefresh =
        !horizontalRef.current &&
        !refreshingRef.current &&
        pullRef.current >= PULL_THRESHOLD

      if (!shouldRefresh) {
        setPullBoth(0)
        return
      }

      refreshingRef.current = true
      setRefreshing(true)
      setPullBoth(PULL_THRESHOLD)
      try {
        await onRefreshRef.current()
      } catch {
        /* page-level errors surface in-page */
      } finally {
        refreshingRef.current = false
        setRefreshing(false)
        setPullBoth(0)
      }
    }

    const onTouchEnd = () => {
      void finish()
    }

    const onTouchCancel = () => {
      trackingRef.current = false
      horizontalRef.current = false
      if (!refreshingRef.current) setPullBoth(0)
    }

    // non-passive touchmove so we can preventDefault only while pulling
    document.addEventListener('touchstart', onTouchStart, { passive: true })
    document.addEventListener('touchmove', onTouchMove, { passive: false })
    document.addEventListener('touchend', onTouchEnd, { passive: true })
    document.addEventListener('touchcancel', onTouchCancel, { passive: true })

    return () => {
      document.removeEventListener('touchstart', onTouchStart)
      document.removeEventListener('touchmove', onTouchMove)
      document.removeEventListener('touchend', onTouchEnd)
      document.removeEventListener('touchcancel', onTouchCancel)
    }
  }, [active])

  return {
    pull,
    armed: pull >= PULL_THRESHOLD && !refreshing,
    refreshing,
  }
}

export const PTR_THRESHOLD = PULL_THRESHOLD
