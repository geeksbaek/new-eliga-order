/**
 * Scroll helpers for expanded dining groups.
 * Expand + scroll share one 280ms ease so motion does not stutter.
 */

/** Bumps to cancel an in-flight rAF scroll when another group opens. */
let scrollGen = 0

/** Match `.dining-group-panel` height transition. */
const EXPAND_MS = 280

function viewBounds(marginTop: number, marginBottom: number) {
  const vv = window.visualViewport
  const viewTop = (vv?.offsetTop ?? 0) + marginTop
  let viewBottom = vv ? vv.offsetTop + vv.height : window.innerHeight

  const dock = document.querySelector('.cart-dock') as HTMLElement | null
  if (dock) {
    const t = dock.getBoundingClientRect().top
    if (Number.isFinite(t) && t < viewBottom) viewBottom = t
  } else {
    const tab = document.querySelector('.tabbar') as HTMLElement | null
    if (tab) {
      viewBottom = Math.min(viewBottom, tab.getBoundingClientRect().top)
    }
  }

  return { viewTop, viewBottom: viewBottom - marginBottom }
}

/** Same family as CSS cubic-bezier(0.32, 0.72, 0, 1) — ease-out, no overshoot. */
function easeOutExpand(t: number): number {
  // Closest simple curve to the panel transition without solving bezier roots
  return 1 - (1 - t) ** 3
}

function prefersReducedMotion(): boolean {
  try {
    return window.matchMedia('(prefers-reduced-motion: reduce)').matches
  } catch {
    return false
  }
}

/**
 * Compute how far to scroll so `el` of given height sits in the visible band.
 * Positive = scroll down.
 */
export function computeScrollDelta(
  el: HTMLElement,
  height: number,
  opts?: { marginTop?: number; marginBottom?: number },
): number {
  const marginTop = opts?.marginTop ?? 8
  const marginBottom = opts?.marginBottom ?? 12
  const { viewTop, viewBottom } = viewBounds(marginTop, marginBottom)
  const avail = Math.max(0, viewBottom - viewTop)

  const top = el.getBoundingClientRect().top
  const bottom = top + height

  if (top >= viewTop - 1 && bottom <= viewBottom + 1) return 0

  if (height <= avail) {
    const needDown = bottom - viewBottom
    const maxDown = top - viewTop
    if (needDown > 0) return maxDown >= needDown ? needDown : maxDown
    if (top < viewTop) return top - viewTop
    return 0
  }
  // Taller than viewport: pin header
  return top - viewTop
}

/**
 * Scroll window so `el` fits above chrome.
 * Prefer scrollExpandedDiningGroup for accordion open (synced animation).
 */
export function scrollBlockIntoView(
  el: HTMLElement,
  opts?: {
    behavior?: ScrollBehavior
    marginTop?: number
    marginBottom?: number
    predictedHeight?: number
  },
): void {
  const behavior = opts?.behavior ?? 'smooth'
  const rendered = el.getBoundingClientRect().height
  const height = Math.max(
    opts?.predictedHeight != null && opts.predictedHeight > 0
      ? opts.predictedHeight
      : 0,
    rendered,
  )
  const delta = computeScrollDelta(el, height, opts)
  if (Math.abs(delta) < 1) return
  window.scrollBy({ top: delta, left: 0, behavior })
}

/** Head + body content height (works under 0fr collapse). */
export function predictedDiningGroupHeight(el: HTMLElement): number {
  const head = el.querySelector('.dining-group-head') as HTMLElement | null
  const body = el.querySelector('.dining-group-body') as HTMLElement | null
  const headH = head?.offsetHeight ?? 0
  const bodyH = body?.scrollHeight ?? 0
  return headH + bodyH + 2
}

/**
 * One continuous scroll over the same 280ms as the height expand.
 * Avoids smooth+instant double jumps that felt choppy.
 */
export function scrollExpandedDiningGroup(
  el: HTMLElement | null | undefined,
): void {
  if (!el) return
  const gen = ++scrollGen

  const start = () => {
    if (gen !== scrollGen) return

    const height = Math.max(
      predictedDiningGroupHeight(el),
      el.getBoundingClientRect().height,
    )
    const delta = computeScrollDelta(el, height)
    if (Math.abs(delta) < 1) return

    if (prefersReducedMotion()) {
      window.scrollBy({ top: delta, left: 0, behavior: 'instant' as ScrollBehavior })
      return
    }

    const from = window.scrollY
    // Target document Y — re-read max in case content shorter than expected
    const to = from + delta
    const t0 = performance.now()

    const step = (now: number) => {
      if (gen !== scrollGen) return
      const t = Math.min(1, (now - t0) / EXPAND_MS)
      const y = from + (to - from) * easeOutExpand(t)
      window.scrollTo({ top: y, left: 0, behavior: 'instant' as ScrollBehavior })
      if (t < 1) {
        requestAnimationFrame(step)
      }
    }
    requestAnimationFrame(step)
  }

  // One frame so `is-open` styles are applied and body metrics are valid
  requestAnimationFrame(start)
}
