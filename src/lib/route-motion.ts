/**
 * Route keys for page enter animations.
 * Cafe list + menu detail share one key so CafeShopShell stays mounted.
 */
export type MainTab = 'home' | 'dining' | 'cafe' | 'orders'

export function mainTabFromPath(path: string): MainTab {
  if (path.startsWith('/dining')) return 'dining'
  // `/orders` before `/order` — startsWith('/order') would match both
  if (path.startsWith('/orders')) return 'orders'
  if (
    path.startsWith('/cafe') ||
    path.startsWith('/cart') ||
    path.startsWith('/order')
  ) {
    return 'cafe'
  }
  return 'home'
}

export const MAIN_TAB_ORDER: MainTab[] = ['home', 'dining', 'cafe', 'orders']

export function mainTabIndex(tab: MainTab): number {
  const i = MAIN_TAB_ORDER.indexOf(tab)
  return i >= 0 ? i : 0
}

/**
 * Stable key for the page shell animation.
 * - `/cafe/5` and `/cafe/5/menu` → same key (preserve list mount)
 * - `/` vs `/dining/7` → different keys (animate)
 */
export function pageViewKey(pathname: string): string {
  if (pathname.startsWith('/cafe/')) {
    const m = pathname.match(/^\/cafe\/[^/]+/)
    return m ? m[0] : pathname
  }
  if (pathname.startsWith('/order')) return '/order'
  return pathname || '/'
}
