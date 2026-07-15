import { useCallback, useMemo, useState } from 'react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { useShop } from '../hooks/useShop'
import { usePullToRefresh } from '../hooks/usePullToRefresh'
import { useScrollRestore } from '../hooks/useScrollRestore'
import { cartGrandTotal } from '../lib/cart-math'
import { formatWon } from '../lib/format'
import { cacheInvalidate } from '../lib/query-cache'
import {
  CAFETERIA_SHOP_ID,
  DEFAULT_CAFE_SHOP_ID,
  canOrderFromShop,
  isCafeShop,
  isCafeteriaShop,
  resolveShopType,
} from '../lib/shop-rules'
import { MealNotifyRunner } from './MealNotifyRunner'
import { PullToRefreshIndicator } from './PullToRefresh'
import { IconCup, IconHome, IconReceipt, IconUtensils } from './Icons'

export function Layout() {
  const {
    cartCountAll,
    cartTotal,
    cartCountByShop,
    cartsByShop,
    selectedShop,
    selectedShopId,
    selectShop,
    shops,
    refreshShops,
    refreshCafePlans,
    refreshAllCafeCarts,
  } = useShop()
  const navigate = useNavigate()
  const location = useLocation()
  // Remount page tree after pull-to-refresh so load effects re-run on cold cache.
  const [contentKey, setContentKey] = useState(0)
  // Note: pages that manage their own restore also call useScrollRestore;
  // double-call is ok — last effect wins for the active page key.
  useScrollRestore()

  const handlePullRefresh = useCallback(async () => {
    cacheInvalidate()
    try {
      sessionStorage.removeItem(
        `eliga:scroll:${location.pathname}${location.search}`,
      )
    } catch {
      /* private mode */
    }
    window.scrollTo(0, 0)
    await refreshShops()
    await Promise.all([
      refreshCafePlans({ force: true }),
      refreshAllCafeCarts({ force: true }),
    ])
    setContentKey((k) => k + 1)
  }, [
    location.pathname,
    location.search,
    refreshShops,
    refreshCafePlans,
    refreshAllCafeCarts,
  ])

  // Standalone PWA only — mobile Chrome keeps native pull-to-refresh.
  const ptr = usePullToRefresh({ onRefresh: handlePullRefresh })

  const path = location.pathname
  const hideCartDock =
    path.startsWith('/cart') ||
    path.startsWith('/order') ||
    path.startsWith('/login') ||
    path.startsWith('/settings')

  /** Cafe menu URL shop (not favorites). Dock follows this shop's cart only. */
  const viewingCafeId = useMemo(() => {
    const m = path.match(/^\/cafe\/(\d+)(?:\/|$)/)
    if (!m) return null
    const n = Number(m[1])
    return Number.isFinite(n) ? n : null
  }, [path])

  const dockShopId = viewingCafeId ?? selectedShopId
  const dockCount =
    dockShopId != null ? (cartCountByShop[dockShopId] ?? 0) : 0
  const dockTotal =
    dockShopId != null && cartsByShop[dockShopId]
      ? cartGrandTotal(cartsByShop[dockShopId].items)
      : cartTotal
  const dockShop =
    shops.find((s) => s.shopId === dockShopId) ??
    (dockShopId != null
      ? {
          shopId: dockShopId,
          name: selectedShop?.shopId === dockShopId ? selectedShop.name : '카페',
          type: resolveShopType(dockShopId),
          open: true,
        }
      : selectedShop)

  // On cafe page: hide dock when that shop's cart is empty (even if others aren't)
  // Favorites / non-cafe routes: still require the dock shop to have items
  const showCartDock =
    !hideCartDock &&
    dockCount > 0 &&
    canOrderFromShop(dockShop)

  const diningShop =
    shops.find((s) => isCafeteriaShop(s.type) || s.shopId === CAFETERIA_SHOP_ID) ??
    null
  const diningPath = `/dining/${diningShop?.shopId ?? CAFETERIA_SHOP_ID}`

  const cafeShop =
    shops.find((s) => s.shopId === selectedShop?.shopId && isCafeShop(s.type)) ??
    shops.find((s) => s.shopId === DEFAULT_CAFE_SHOP_ID) ??
    shops.find((s) => isCafeShop(s.type)) ??
    null
  const cafePath = `/cafe/${cafeShop?.shopId ?? DEFAULT_CAFE_SHOP_ID}`

  const tab =
    path === '/'
      ? 'home'
      : path.startsWith('/dining')
        ? 'dining'
        : path.startsWith('/orders')
          ? 'orders'
          : path.startsWith('/cafe') ||
              path.startsWith('/cart') ||
              path.startsWith('/order')
            ? 'cafe'
            : 'home'

  // Tab badge: all shops (hint that another cafe has items)
  const tabBadge = cartCountAll

  return (
    <div className="app-shell" data-tab={tab}>
      <MealNotifyRunner />
      <PullToRefreshIndicator state={ptr} />
      <main className="app-main">
        <Outlet key={contentKey} />
      </main>

      {/* Fixed overlay: always mounted to avoid layout jump when cart appears */}
      <div
        className={`cart-dock${showCartDock ? ' is-visible' : ''}`}
        aria-hidden={!showCartDock}
      >
        {showCartDock && (
          <button
            type="button"
            className="cart-dock-btn"
            onClick={() => {
              if (dockShopId != null) selectShop(dockShopId)
              navigate('/cart')
            }}
          >
            <span className="cart-dock-count" aria-hidden>
              {dockCount}
            </span>
            <span className="cart-dock-meta">
              <strong>{formatWon(dockTotal)}</strong>
              <span>{dockShop?.name ?? '카페'}</span>
            </span>
            <span className="cart-dock-cta">장바구니</span>
          </button>
        )}
      </div>

      <nav className="tabbar" aria-label="주요 메뉴">
        <NavLink
          to="/"
          end
          className={() => `tabbar-item${tab === 'home' ? ' is-active' : ''}`}
        >
          <IconHome />
          <span>홈</span>
        </NavLink>
        <NavLink
          to={diningPath}
          className={() => `tabbar-item${tab === 'dining' ? ' is-active' : ''}`}
        >
          <IconUtensils />
          <span>식단</span>
        </NavLink>
        <NavLink
          to={cafePath}
          className={() => `tabbar-item${tab === 'cafe' ? ' is-active' : ''}`}
        >
          <span className="tabbar-icon-wrap">
            <IconCup />
            <span
              className={`tabbar-badge${tabBadge > 0 ? ' is-on' : ''}`}
              aria-hidden={tabBadge <= 0}
            >
              {tabBadge > 9 ? '9+' : tabBadge || ''}
            </span>
          </span>
          <span>카페</span>
        </NavLink>
        <NavLink
          to="/orders"
          className={() => `tabbar-item${tab === 'orders' ? ' is-active' : ''}`}
        >
          <IconReceipt />
          <span>내역</span>
        </NavLink>
      </nav>
    </div>
  )
}
