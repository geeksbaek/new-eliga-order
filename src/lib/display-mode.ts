/**
 * Display mode helpers for PWA vs in-browser Chrome.
 * Custom pull-to-refresh must only run when the OS/browser does not
 * already provide a native one (installed standalone / iOS home-screen).
 */

export function isStandaloneDisplay(
  win: Window & { navigator: Navigator & { standalone?: boolean } } = window,
): boolean {
  try {
    if (win.matchMedia('(display-mode: standalone)').matches) return true
    if (win.matchMedia('(display-mode: fullscreen)').matches) return true
    if (win.matchMedia('(display-mode: minimal-ui)').matches) return true
  } catch {
    /* matchMedia unavailable */
  }
  // iOS Safari "Add to Home Screen" (pre-manifest display-mode support)
  if (win.navigator.standalone === true) return true
  return false
}

/** Subscribe to display-mode changes (rare; useful for tests / multi-window). */
export function subscribeStandaloneDisplay(
  onChange: (standalone: boolean) => void,
  win: Window = window,
): () => void {
  const medias = [
    '(display-mode: standalone)',
    '(display-mode: fullscreen)',
    '(display-mode: minimal-ui)',
  ]
  const mqls: MediaQueryList[] = []
  const fire = () => onChange(isStandaloneDisplay(win as never))
  for (const q of medias) {
    try {
      const mql = win.matchMedia(q)
      mql.addEventListener('change', fire)
      mqls.push(mql)
    } catch {
      /* ignore */
    }
  }
  return () => {
    for (const mql of mqls) mql.removeEventListener('change', fire)
  }
}
