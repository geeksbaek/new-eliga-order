/**
 * Cafe menu favorites (localStorage).
 * Entries keep displayId + shopId so multi-shop favorites can open the right menu/cart.
 */

const KEY = 'eliga.cafe.favorites'

/** Same-tab signal so header badge updates without focus/visibility refresh. */
export const FAVORITES_CHANGED_EVENT = 'eliga:cafe-favorites'

export type CafeFavorite = {
  displayId: number
  shopId: number
}

function notifyFavoritesChanged(entries: CafeFavorite[]): void {
  try {
    if (typeof window === 'undefined') return
    window.dispatchEvent(
      new CustomEvent(FAVORITES_CHANGED_EVENT, {
        detail: { count: entries.length, entries },
      }),
    )
  } catch {
    /* ignore (SSR / non-DOM) */
  }
}

function readEntries(): CafeFavorite[] {
  try {
    const raw = localStorage.getItem(KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw) as unknown
    if (!Array.isArray(parsed)) return []
    const out: CafeFavorite[] = []
    const seen = new Set<string>()
    for (const v of parsed) {
      // Legacy: bare displayId numbers
      if (typeof v === 'number' || (typeof v === 'string' && v.trim() !== '')) {
        const displayId = Number(v)
        if (!Number.isFinite(displayId) || displayId <= 0) continue
        const key = `0:${displayId}`
        if (seen.has(key)) continue
        seen.add(key)
        out.push({ displayId, shopId: 0 })
        continue
      }
      if (!v || typeof v !== 'object') continue
      const o = v as Record<string, unknown>
      const displayId = Number(o.displayId)
      const shopId = Number(o.shopId)
      if (!Number.isFinite(displayId) || displayId <= 0) continue
      if (!Number.isFinite(shopId) || shopId < 0) continue
      const key = `${shopId}:${displayId}`
      if (seen.has(key)) continue
      seen.add(key)
      out.push({ displayId, shopId })
    }
    return out
  } catch {
    return []
  }
}

function writeEntries(entries: CafeFavorite[]): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(entries))
  } catch {
    /* quota / private mode */
  }
  notifyFavoritesChanged(entries)
}

export function loadFavorites(): CafeFavorite[] {
  return readEntries()
}

export function loadFavoriteDisplayIdSet(): Set<number> {
  return new Set(readEntries().map((e) => e.displayId))
}

export function isFavorite(
  displayId: number,
  shopId?: number,
  list?: CafeFavorite[],
): boolean {
  const entries = list ?? readEntries()
  if (shopId != null && shopId > 0) {
    return entries.some(
      (e) => e.displayId === displayId && (e.shopId === shopId || e.shopId === 0),
    )
  }
  return entries.some((e) => e.displayId === displayId)
}

/**
 * Toggle favorite for a menu card.
 * Returns the next entry list (insertion order preserved).
 */
export function toggleFavorite(
  displayId: number,
  shopId: number,
): CafeFavorite[] {
  const id = Number(displayId)
  const sid = Number(shopId)
  if (!Number.isFinite(id) || id <= 0) return readEntries()
  if (!Number.isFinite(sid) || sid <= 0) return readEntries()

  const cur = readEntries()
  const idx = cur.findIndex(
    (e) => e.displayId === id && (e.shopId === sid || e.shopId === 0),
  )
  let next: CafeFavorite[]
  if (idx >= 0) {
    next = cur.filter((_, i) => i !== idx)
  } else {
    next = [...cur, { displayId: id, shopId: sid }]
  }
  writeEntries(next)
  return next
}

/** @deprecated use toggleFavorite(displayId, shopId) */
export function toggleFavoriteDisplayId(displayId: number): number[] {
  const cur = readEntries()
  const id = Number(displayId)
  if (!Number.isFinite(id) || id <= 0) return cur.map((e) => e.displayId)
  const idx = cur.findIndex((e) => e.displayId === id)
  const next =
    idx >= 0
      ? cur.filter((_, i) => i !== idx)
      : [...cur, { displayId: id, shopId: 0 }]
  writeEntries(next)
  return next.map((e) => e.displayId)
}

export function isFavoriteDisplayId(
  displayId: number,
  favorites: Set<number> | number[],
): boolean {
  if (favorites instanceof Set) return favorites.has(displayId)
  return favorites.includes(displayId)
}
