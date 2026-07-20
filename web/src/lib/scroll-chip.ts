/**
 * Keep a chip/pill visible inside a horizontal scroller without jumping the page.
 */

export function ensureHorizontalVisible(
  el: HTMLElement | null | undefined,
  padding = 12,
): void {
  if (!el) return
  const scroller = el.closest(
    '.shop-pills-scroll, .chip-strip, [data-hscroll]',
  ) as HTMLElement | null
  if (!scroller) {
    el.scrollIntoView({ behavior: 'smooth', inline: 'nearest', block: 'nearest' })
    return
  }

  const er = el.getBoundingClientRect()
  const sr = scroller.getBoundingClientRect()
  if (er.left < sr.left + padding) {
    scroller.scrollLeft -= sr.left + padding - er.left
  } else if (er.right > sr.right - padding) {
    scroller.scrollLeft += er.right - (sr.right - padding)
  }
}
