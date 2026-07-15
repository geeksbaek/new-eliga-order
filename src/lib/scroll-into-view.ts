/**
 * Scroll helpers for keeping expanded dining groups fully on screen
 * above the fixed tab bar / cart dock.
 */

/** Invalidate in-flight smooth scrolls when the user opens another group. */
let scrollGen = 0

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

/**
 * Scroll window so `el` fits in the visible band above chrome.
 * Uses predictedHeight while CSS accordion height is still animating.
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
  const marginTop = opts?.marginTop ?? 8
  const marginBottom = opts?.marginBottom ?? 12
  const { viewTop, viewBottom } = viewBounds(marginTop, marginBottom)
  const avail = Math.max(0, viewBottom - viewTop)

  const top = el.getBoundingClientRect().top
  const rendered = el.getBoundingClientRect().height
  const height = Math.max(
    opts?.predictedHeight != null && opts.predictedHeight > 0
      ? opts.predictedHeight
      : 0,
    rendered,
  )
  const bottom = top + height

  // Already fully visible
  if (top >= viewTop - 1 && bottom <= viewBottom + 1) return

  let delta = 0
  if (height <= avail) {
    // Scroll down enough to reveal bottom; never hide the top if it fits.
    const needDown = bottom - viewBottom
    const maxDown = top - viewTop
    if (needDown > 0) {
      delta = maxDown >= needDown ? needDown : maxDown
    } else if (top < viewTop) {
      delta = top - viewTop
    }
  } else {
    // Taller than viewport: pin header under the top margin
    delta = top - viewTop
  }

  if (Math.abs(delta) < 1) return
  window.scrollBy({ top: delta, left: 0, behavior })
}

/** Head + body content height (body.scrollHeight works even under 0fr collapse). */
export function predictedDiningGroupHeight(el: HTMLElement): number {
  const head = el.querySelector('.dining-group-head') as HTMLElement | null
  const body = el.querySelector('.dining-group-body') as HTMLElement | null
  const headH = head?.offsetHeight ?? 0
  const bodyH = body?.scrollHeight ?? 0
  return headH + bodyH + 2
}

/**
 * After a dining group expands: scroll so the open card is as fully visible
 * as possible. Call only after React has committed `is-open`.
 *
 * 1) smooth scroll using predicted final height (mid-animation)
 * 2) instant correction after the 0.28s height transition
 */
export function scrollExpandedDiningGroup(
  el: HTMLElement | null | undefined,
  opts?: { behavior?: ScrollBehavior },
): void {
  if (!el) return
  const gen = ++scrollGen
  const preferred = opts?.behavior ?? 'smooth'

  const run = (behavior: ScrollBehavior) => {
    if (gen !== scrollGen) return
    scrollBlockIntoView(el, {
      behavior,
      predictedHeight: predictedDiningGroupHeight(el),
    })
  }

  // Double rAF: wait for style/layout with is-open applied
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      if (gen !== scrollGen) return
      run(preferred)
      // Accordion transition is 0.28s — snap once height is final
      window.setTimeout(() => run('instant' as ScrollBehavior), 300)
    })
  })
}
