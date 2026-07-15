import { useEffect } from 'react'
import {
  anyMealNotifyEnabled,
  loadNotificationPrefs,
  tickMealNotifications,
} from '../lib/meal-notify'

const POLL_MS = 30_000

/**
 * Background ticker for meal menu notifications.
 * Mount once inside the authenticated shell.
 */
export function MealNotifyRunner() {
  useEffect(() => {
    let cancelled = false

    async function tick() {
      if (cancelled) return
      if (!anyMealNotifyEnabled(loadNotificationPrefs())) return
      try {
        await tickMealNotifications()
      } catch {
        /* ignore */
      }
    }

    void tick()
    const id = window.setInterval(() => void tick(), POLL_MS)

    function onVis() {
      if (document.visibilityState === 'visible') void tick()
    }
    function onPrefs() {
      void tick()
    }

    document.addEventListener('visibilitychange', onVis)
    window.addEventListener('eliga:notify-prefs', onPrefs)

    return () => {
      cancelled = true
      window.clearInterval(id)
      document.removeEventListener('visibilitychange', onVis)
      window.removeEventListener('eliga:notify-prefs', onPrefs)
    }
  }, [])

  return null
}
