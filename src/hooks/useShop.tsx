import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { fetchCafeSalesPlan, fetchCart, fetchShops } from '../api/eliga'
import {
  evaluateCafeHours,
  type CafeHoursStatus,
  type CafeSalesPlan,
} from '../lib/cafe-hours'
import { cartGrandTotal, cartItemCount } from '../lib/cart-math'
import {
  canOrderFromShop,
  isCafeShop,
  preferShopId,
  resolveShopType,
} from '../lib/shop-rules'
import { loadLastShopId, saveLastShopId } from '../lib/storage'
import type { Cart, Shop } from '../lib/types'

/** Cart chip switching reuses memory cache; network only when missing/stale/forced. */
const CART_TTL_MS = 3 * 60 * 1000
/** Sales-plan openYn flips at open/close — refresh often enough. */
const PLAN_TTL_MS = 60 * 1000

export type RefreshCartOpts = {
  /** Do not flip cartLoading (background reconcile after optimistic UI). */
  silent?: boolean
  /** Defaults to selectedShopId */
  shopId?: number
  /** Always hit the network (after checkout, pull-to-refresh, etc.) */
  force?: boolean
}

interface ShopContextValue {
  shops: Shop[]
  shopsLoading: boolean
  shopsError: string | null
  selectedShopId: number | null
  selectedShop: Shop | null
  selectShop: (shopId: number) => void
  refreshShops: () => Promise<void>
  /** Cart for the currently selected shop (checkout / cart page). */
  cart: Cart
  cartLoading: boolean
  cartTotal: number
  /** Item count for the selected shop only */
  cartCount: number
  /** Sum of items across all cafe carts (dock / badges) */
  cartCountAll: number
  /** Per-shop item counts for chips */
  cartCountByShop: Record<number, number>
  /** All loaded cafe carts (favorites multi-shop qty) */
  cartsByShop: Record<number, Cart>
  getCart: (shopId: number) => Cart
  refreshCart: (opts?: RefreshCartOpts) => Promise<Cart | null>
  /** Prefetch carts for every orderable cafe shop */
  refreshAllCafeCarts: (opts?: { force?: boolean }) => Promise<void>
  /** Immediate local cart write for a shop (optimistic UI). */
  setCartLocal: (
    next: Cart | ((prev: Cart) => Cart),
    shopId?: number,
  ) => void
  /**
   * Always-current cart for the selected shop (mutation queues).
   * Prefer getCart(shopId) when mutating a non-selected shop.
   */
  cartRef: React.MutableRefObject<Cart>
  canOrder: boolean
  /** Cafe sales plans by shopId (null = not loaded / failed). */
  cafePlansByShop: Record<number, CafeSalesPlan | null>
  /** Evaluate order window for a cafe (recomputes from clock each call). */
  getCafeHours: (shopId: number | null | undefined) => CafeHoursStatus
  /** True when selected cafe is within operating hours for orders. */
  isSelectedCafeOpen: boolean
  refreshCafePlans: (opts?: { force?: boolean }) => Promise<void>
}

const ShopContext = createContext<ShopContextValue | null>(null)

const EMPTY_CART: Cart = { cartId: null, items: [] }

function emptyCart(shopId?: number): Cart {
  return shopId != null ? { cartId: null, shopId, items: [] } : EMPTY_CART
}

export function ShopProvider({ children }: { children: ReactNode }) {
  const [shops, setShops] = useState<Shop[]>([])
  const [shopsLoading, setShopsLoading] = useState(false)
  const [shopsError, setShopsError] = useState<string | null>(null)
  const [selectedShopId, setSelectedShopId] = useState<number | null>(null)
  const [cartsByShop, setCartsByShop] = useState<Record<number, Cart>>({})
  const [cartLoading, setCartLoading] = useState(false)
  const [cafePlansByShop, setCafePlansByShop] = useState<
    Record<number, CafeSalesPlan | null>
  >({})
  /** Forces re-render so hours recompute past open/close boundaries. */
  const [hoursTick, setHoursTick] = useState(0)
  const cartsRef = useRef<Record<number, Cart>>({})
  /** Always-current shop list (pull-to-refresh / async callbacks). */
  const shopsRef = useRef<Shop[]>([])
  /** Last successful network (or optimistic) write time per shop */
  const cartFetchedAtRef = useRef<Record<number, number>>({})
  const planFetchedAtRef = useRef<Record<number, number>>({})
  const selectedShopIdRef = useRef<number | null>(null)
  selectedShopIdRef.current = selectedShopId
  shopsRef.current = shops

  const cartRef = useRef<Cart>(EMPTY_CART)

  const syncCartRef = useCallback((sid: number | null, map: Record<number, Cart>) => {
    if (sid != null && map[sid]) cartRef.current = map[sid]
    else if (sid != null) cartRef.current = emptyCart(sid)
    else cartRef.current = EMPTY_CART
  }, [])

  const touchCartCache = useCallback((sid: number) => {
    cartFetchedAtRef.current[sid] = Date.now()
  }, [])

  const isCartCacheFresh = useCallback((sid: number): boolean => {
    const at = cartFetchedAtRef.current[sid]
    if (at == null) return false
    if (!cartsRef.current[sid]) return false
    return Date.now() - at <= CART_TTL_MS
  }, [])

  const setCartLocal = useCallback(
    (next: Cart | ((prev: Cart) => Cart), shopId?: number) => {
      const sid = shopId ?? selectedShopIdRef.current
      if (sid == null) return
      setCartsByShop((prev) => {
        const base = prev[sid] ?? emptyCart(sid)
        const resolved = typeof next === 'function' ? next(base) : next
        const withShop: Cart = {
          ...resolved,
          shopId: resolved.shopId ?? sid,
        }
        const map = { ...prev, [sid]: withShop }
        cartsRef.current = map
        touchCartCache(sid)
        if (selectedShopIdRef.current === sid) cartRef.current = withShop
        return map
      })
    },
    [touchCartCache],
  )

  const getCart = useCallback((shopId: number): Cart => {
    return cartsRef.current[shopId] ?? emptyCart(shopId)
  }, [])

  const refreshShops = useCallback(async () => {
    setShopsLoading(true)
    setShopsError(null)
    try {
      const list = await fetchShops()
      const normalized = list.map((s) => ({
        ...s,
        type: resolveShopType(s.shopId, s.type),
      }))
      shopsRef.current = normalized
      setShops(normalized)
      setSelectedShopId((prev) => {
        if (prev != null && normalized.some((s) => s.shopId === prev)) return prev
        return preferShopId(loadLastShopId(), normalized)
      })
    } catch (e) {
      setShopsError(
        e instanceof Error ? e.message : '매장 목록을 불러오지 못했습니다',
      )
      shopsRef.current = []
      setShops([])
    } finally {
      setShopsLoading(false)
    }
  }, [])

  const selectedShop =
    shops.find((s) => s.shopId === selectedShopId) ?? null
  const canOrder = canOrderFromShop(selectedShop)

  const refreshCafePlans = useCallback(async (opts?: { force?: boolean }) => {
    const force = Boolean(opts?.force)
    const cafes = shopsRef.current.filter(
      (s) => isCafeShop(s.type) && canOrderFromShop(s),
    )
    if (!cafes.length) return
    const now = Date.now()
    await Promise.all(
      cafes.map(async (s) => {
        const at = planFetchedAtRef.current[s.shopId]
        if (!force && at != null && now - at <= PLAN_TTL_MS) {
          return
        }
        try {
          const plan = await fetchCafeSalesPlan(s.shopId)
          planFetchedAtRef.current[s.shopId] = Date.now()
          setCafePlansByShop((prev) => {
            const prevP = prev[s.shopId]
            if (
              prevP &&
              plan &&
              prevP.open === plan.open &&
              prevP.pauseOrder === plan.pauseOrder &&
              prevP.nowBreak === plan.nowBreak &&
              prevP.autoOpenTime === plan.autoOpenTime &&
              prevP.autoCloseTime === plan.autoCloseTime &&
              prevP.lastOrderUse === plan.lastOrderUse &&
              prevP.lastOrderTime === plan.lastOrderTime
            ) {
              return prev
            }
            return { ...prev, [s.shopId]: plan }
          })
        } catch (e) {
          console.warn('cafe sales-plan failed', s.shopId, e)
          planFetchedAtRef.current[s.shopId] = Date.now()
          setCafePlansByShop((prev) =>
            s.shopId in prev ? prev : { ...prev, [s.shopId]: null },
          )
        }
      }),
    )
  }, [])

  const getCafeHours = useCallback(
    (shopId: number | null | undefined): CafeHoursStatus => {
      void hoursTick // depend on tick for live status flips
      if (shopId == null || !Number.isFinite(shopId)) {
        return evaluateCafeHours(null)
      }
      // Not loaded yet, or fetch failed → do not hard-block (server still enforces)
      if (!(shopId in cafePlansByShop) || cafePlansByShop[shopId] == null) {
        return {
          orderable: true,
          reason: 'unknown',
          hoursLabel: '',
          statusLabel: '',
          message: '영업 정보를 확인하는 중입니다',
          plan: null,
        }
      }
      return evaluateCafeHours(cafePlansByShop[shopId])
    },
    [cafePlansByShop, hoursTick],
  )

  const isSelectedCafeOpen =
    selectedShopId != null &&
    canOrder &&
    getCafeHours(selectedShopId).orderable

  const refreshCart = useCallback(
    async (opts?: RefreshCartOpts): Promise<Cart | null> => {
      const silent = Boolean(opts?.silent)
      const force = Boolean(opts?.force)
      const sid = opts?.shopId ?? selectedShopIdRef.current
      if (sid == null) {
        return EMPTY_CART
      }
      const shopMeta =
        shopsRef.current.find((s) => s.shopId === sid) ?? {
          shopId: sid,
          type: resolveShopType(sid),
          name: '',
          open: false,
        }
      if (!canOrderFromShop(shopMeta)) {
        setCartLocal(emptyCart(sid), sid)
        return emptyCart(sid)
      }

      // Chip switch / re-entry: reuse in-memory cart while TTL is valid
      if (!force && isCartCacheFresh(sid)) {
        const hit = getCart(sid)
        if (selectedShopIdRef.current === sid) {
          cartRef.current = hit
          setCartLoading(false)
        }
        return hit
      }

      if (!silent && sid === selectedShopIdRef.current) setCartLoading(true)
      try {
        const next = await fetchCart(sid)
        const withShop = { ...next, shopId: next.shopId ?? sid }
        setCartLocal(withShop, sid)
        return withShop
      } catch (e) {
        console.warn('cart refresh failed', e)
        if (!silent) {
          setCartLocal(emptyCart(sid), sid)
          return emptyCart(sid)
        }
        return getCart(sid)
      } finally {
        if (!silent && sid === selectedShopIdRef.current) setCartLoading(false)
      }
    },
    [setCartLocal, getCart, isCartCacheFresh],
  )

  const refreshAllCafeCarts = useCallback(
    async (opts?: { force?: boolean }) => {
      const force = Boolean(opts?.force)
      const cafes = shopsRef.current.filter(
        (s) => isCafeShop(s.type) && canOrderFromShop(s),
      )
      if (!cafes.length) return
      await Promise.all(
        cafes.map((s) =>
          refreshCart({
            shopId: s.shopId,
            silent: true,
            force,
          }),
        ),
      )
    },
    [refreshCart],
  )

  useEffect(() => {
    void refreshShops()
  }, [refreshShops])

  // Selection change: paint cached cart immediately; network only if stale/missing
  useEffect(() => {
    if (selectedShopId == null) {
      cartRef.current = EMPTY_CART
      return
    }
    syncCartRef(selectedShopId, cartsRef.current)
    void refreshCart({ shopId: selectedShopId, silent: true })
  }, [selectedShopId, refreshCart, syncCartRef])

  // After shops load, warm cafe carts once (skips shops already fresh)
  useEffect(() => {
    if (!shops.length) return
    void refreshAllCafeCarts()
  }, [shops, refreshAllCafeCarts])

  // Load sales plans for every cafe; soft revalidate on an interval
  useEffect(() => {
    if (!shops.length) return
    void refreshCafePlans()
  }, [shops, refreshCafePlans])

  useEffect(() => {
    const id = window.setInterval(() => {
      setHoursTick((n) => n + 1)
      void refreshCafePlans()
    }, PLAN_TTL_MS)
    const onFocus = () => {
      setHoursTick((n) => n + 1)
      void refreshCafePlans({ force: true })
    }
    const onVis = () => {
      if (document.visibilityState === 'visible') onFocus()
    }
    window.addEventListener('focus', onFocus)
    document.addEventListener('visibilitychange', onVis)
    return () => {
      window.clearInterval(id)
      window.removeEventListener('focus', onFocus)
      document.removeEventListener('visibilitychange', onVis)
    }
  }, [refreshCafePlans])

  const selectShop = useCallback((shopId: number) => {
    setSelectedShopId(shopId)
    saveLastShopId(shopId)
  }, [])

  const cart =
    selectedShopId != null
      ? (cartsByShop[selectedShopId] ?? emptyCart(selectedShopId))
      : EMPTY_CART

  const cartTotal = cartGrandTotal(cart.items)
  const cartCount = cartItemCount(cart.items)

  const cartCountByShop = useMemo(() => {
    const out: Record<number, number> = {}
    for (const [k, c] of Object.entries(cartsByShop)) {
      const sid = Number(k)
      out[sid] = cartItemCount(c.items)
    }
    return out
  }, [cartsByShop])

  const cartCountAll = useMemo(
    () => Object.values(cartCountByShop).reduce((s, n) => s + n, 0),
    [cartCountByShop],
  )

  const value = useMemo(
    () => ({
      shops,
      shopsLoading,
      shopsError,
      selectedShopId,
      selectedShop,
      selectShop,
      refreshShops,
      cart,
      cartLoading,
      cartTotal,
      cartCount,
      cartCountAll,
      cartCountByShop,
      cartsByShop,
      getCart,
      refreshCart,
      refreshAllCafeCarts,
      setCartLocal,
      cartRef,
      canOrder,
      cafePlansByShop,
      getCafeHours,
      isSelectedCafeOpen,
      refreshCafePlans,
    }),
    [
      shops,
      shopsLoading,
      shopsError,
      selectedShopId,
      selectedShop,
      selectShop,
      refreshShops,
      cart,
      cartLoading,
      cartTotal,
      cartCount,
      cartCountAll,
      cartCountByShop,
      cartsByShop,
      getCart,
      refreshCart,
      refreshAllCafeCarts,
      setCartLocal,
      canOrder,
      cafePlansByShop,
      getCafeHours,
      isSelectedCafeOpen,
      refreshCafePlans,
    ],
  )

  return <ShopContext.Provider value={value}>{children}</ShopContext.Provider>
}

export function useShop(): ShopContextValue {
  const ctx = useContext(ShopContext)
  if (!ctx) throw new Error('useShop must be used within ShopProvider')
  return ctx
}
