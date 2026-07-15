/**
 * In-memory page data cache so back navigation can rehydrate without a blank
 * reload. Soft TTL for revalidation; pull-to-refresh forces bypass.
 */

type Entry<T> = { data: T; at: number }

const store = new Map<string, Entry<unknown>>()

const DEFAULT_TTL_MS = 5 * 60 * 1000

export function cacheGet<T>(key: string, maxAgeMs = DEFAULT_TTL_MS): T | null {
  const hit = store.get(key) as Entry<T> | undefined
  if (!hit) return null
  if (Date.now() - hit.at > maxAgeMs) return null
  return hit.data
}

/** Return cached data even if stale (for instant paint on back). */
export function cachePeek<T>(key: string): T | null {
  const hit = store.get(key) as Entry<T> | undefined
  return hit ? hit.data : null
}

/** True when cache exists and is still within TTL (skip soft revalidate). */
export function cacheIsFresh(key: string, maxAgeMs = DEFAULT_TTL_MS): boolean {
  const hit = store.get(key)
  if (!hit) return false
  return Date.now() - hit.at <= maxAgeMs
}

export function cacheSet<T>(key: string, data: T): void {
  store.set(key, { data, at: Date.now() })
}

export function cacheInvalidate(prefix?: string): void {
  if (!prefix) {
    store.clear()
    return
  }
  for (const k of [...store.keys()]) {
    if (k.startsWith(prefix)) store.delete(k)
  }
}

export function cafeMenuKey(shopId: number, categoryId: number | 'all'): string {
  return `cafe:menu:${shopId}:${categoryId}`
}

export function cafeCatsKey(shopId: number): string {
  return `cafe:cats:${shopId}`
}

export function cafeRailKey(shopId: number): string {
  return `cafe:rail:${shopId}`
}

export function cafePlanKey(shopId: number): string {
  return `cafe:plan:${shopId}`
}

export function diningKey(shopId: number, date: string): string {
  return `dining:${shopId}:${date}`
}

export function homeLunchKey(shopId: number, date: string): string {
  return `home:lunch:${shopId}:${date}`
}

export function homeRailKey(shopId: number): string {
  return `home:rail:${shopId}`
}

/** Merged recent orders across all cafe shops (home card). */
export function homeRecentAllKey(): string {
  return 'home:recent:all'
}
