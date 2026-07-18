/**
 * Warm cafe caches in the background so navigation feels instant.
 * Safe to call often — in-flight dedupe + cache freshness prevent storms.
 */
import {
  fetchCafeCategories,
  fetchCafeMenu,
  fetchPopularOrders,
  fetchRecentOrders,
} from '../api/eliga'
import {
  cacheIsFresh,
  cacheSet,
  cafeCatsKey,
  cafeMenuKey,
  cafeRailKey,
} from './query-cache'

export async function prefetchCafeShop(shopId: number): Promise<void> {
  if (!Number.isFinite(shopId) || shopId <= 0) return

  const menuKey = cafeMenuKey(shopId, 'all')
  const catsKey = cafeCatsKey(shopId)
  const railKey = cafeRailKey(shopId)

  const jobs: Promise<unknown>[] = []

  if (!cacheIsFresh(menuKey)) {
    jobs.push(
      fetchCafeMenu(shopId)
        .then((items) => cacheSet(menuKey, items))
        .catch(() => {}),
    )
  }
  if (!cacheIsFresh(catsKey)) {
    jobs.push(
      fetchCafeCategories(shopId)
        .then((cats) =>
          cacheSet(
            catsKey,
            cats.filter((c) => c.mobileUseYn),
          ),
        )
        .catch(() => {}),
    )
  }
  if (!cacheIsFresh(railKey)) {
    jobs.push(
      Promise.all([fetchRecentOrders(shopId), fetchPopularOrders(shopId)])
        .then(([r, p]) =>
          cacheSet(railKey, {
            recent: r.slice(0, 8),
            popular: p.slice(0, 6),
          }),
        )
        .catch(() => {}),
    )
  }

  if (jobs.length) await Promise.all(jobs)
}

/** Schedule prefetch when the browser is idle (home / hover). */
export function schedulePrefetchCafe(shopId: number): void {
  if (!Number.isFinite(shopId) || shopId <= 0) return
  const run = () => {
    void prefetchCafeShop(shopId)
  }
  if (typeof requestIdleCallback === 'function') {
    requestIdleCallback(run, { timeout: 2500 })
  } else {
    setTimeout(run, 400)
  }
}
