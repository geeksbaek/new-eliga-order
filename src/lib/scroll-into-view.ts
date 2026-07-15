/**
 * Scroll the window so `el` fits in the visible area above fixed chrome
 * (cart dock + tab bar). If taller than the viewport, pin the top.
 */

function viewBottomPx(margin: number): number {
  const dock = document.querySelector('.cart-dock') as HTMLElement | null
  if (dock) {
    const top = dock.getBoundingClientRect().top
    if (Number.isFinite(top) && top < window.innerHeight) {
      return top - margin
    }
  }
  const tab = document.querySelector('.tabbar') as HTMLElement | null
  if (tab) {
    return tab.getBoundingClientRect().top - margin
  }
  return window.innerHeight - margin
}

/**
 * Use measured (or predicted) height so we can scroll before a CSS height
 * animation finishes — e.g. dining accordion body still at 0fr mid-transition.
 */
export function scrollBlockIntoView(
  el: HTMLElement,
  opts?: {
    behavior?: ScrollBehavior
    margin?: number
    /** Prefer this height instead of current getBoundingClientRect().height */
    predictedHeight?: number
  },
): void {
  const behavior = opts?.behavior ?? 'smooth'
  const margin = opts?.margin ?? 10
  const viewTop = margin
  const viewBottom = viewBottomPx(margin)
  const avail = Math.max(0, viewBottom - viewTop)

  const top = el.getBoundingClientRect().top
  const height =
    opts?.predictedHeight != null && opts.predictedHeight > 0
      ? opts.predictedHeight
      : el.getBoundingClientRect().height
  const bottom = top + height

  if (top >= viewTop - 1 && bottom <= viewBottom + 1) return

  let delta = 0
  if (height <= avail) {
    if (bottom > viewBottom) delta = bottom - viewBottom
    else if (top < viewTop) delta = top - viewTop
  } else {
    // Content taller than viewport: keep the header in view
    delta = top - viewTop
  }

  if (Math.abs(delta) < 1) return
  window.scrollBy({ top: delta, left: 0, behavior })
}

/** Dining period card: head + body scrollHeight (ignores 0fr collapse). */
export function predictedDiningGroupHeight(el: HTMLElement): number {
  const head = el.querySelector('.dining-group-head') as HTMLElement | null
  const body = el.querySelector('.dining-group-body') as HTMLElement | null
  const headH = head?.offsetHeight ?? 0
  const bodyH = body?.scrollHeight ?? 0
  // border on the card
  return headH + bodyH + 2
}

/**
 * After expanding a dining group, scroll so the open card is as fully
 * visible as possible (waits a frame for `is-open`, uses predicted height).
 */
export function scrollExpandedDiningGroup(
  el: HTMLElement | null | undefined,
  opts?: { behavior?: ScrollBehavior },
): void {
  if (!el) return
  const behavior = opts?.behavior ?? 'smooth'
  const run = () => {
    scrollBlockIntoView(el, {
      behavior,
      predictedHeight: predictedDiningGroupHeight(el),
    })
  }
  // One frame: `is-open` class + layout; body metrics are available even at 0fr
  requestAnimationFrame(() => {
    run()
    // Re-check after height transition ends (content may reflow fonts/images)
    window.setTimeout(run, 300)
  })
}
