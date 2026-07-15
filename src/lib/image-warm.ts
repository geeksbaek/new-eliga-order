/**
 * In-session memory of successfully decoded menu image URLs.
 * On SPA remount (back navigation) we load these eagerly so thumbs
 * paint from disk/memory cache without a lazy-load blank frame.
 */
const warm = new Set<string>()

export function markImageWarm(src: string | null | undefined): void {
  const u = src?.trim()
  if (u) warm.add(u)
}

export function isImageWarm(src: string | null | undefined): boolean {
  const u = src?.trim()
  return Boolean(u && warm.has(u))
}

/** Kick browser decode for list thumbs (fire-and-forget). */
export function warmImageUrls(urls: Array<string | null | undefined>): void {
  if (typeof Image === 'undefined') return
  for (const raw of urls) {
    const u = raw?.trim()
    if (!u || warm.has(u)) continue
    const img = new Image()
    img.decoding = 'async'
    img.onload = () => markImageWarm(u)
    img.src = u
  }
}
