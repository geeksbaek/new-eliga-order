import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import { fetchCart, fetchShops } from '../api/eliga'
import { cartGrandTotal, cartItemCount } from '../lib/cart-math'
import {
  canOrderFromShop,
  preferShopId,
  resolveShopType,
} from '../lib/shop-rules'
import { loadLastShopId, saveLastShopId } from '../lib/storage'
import type { Cart, Shop } from '../lib/types'

interface ShopContextValue {
  shops: Shop[]
  shopsLoading: boolean
  shopsError: string | null
  selectedShopId: number | null
  selectedShop: Shop | null
  selectShop: (shopId: number) => void
  refreshShops: () => Promise<void>
  cart: Cart
  cartLoading: boolean
  cartTotal: number
  cartCount: number
  refreshCart: () => Promise<void>
  canOrder: boolean
}

const ShopContext = createContext<ShopContextValue | null>(null)

const EMPTY_CART: Cart = { cartId: null, items: [] }

export function ShopProvider({ children }: { children: ReactNode }) {
  const [shops, setShops] = useState<Shop[]>([])
  const [shopsLoading, setShopsLoading] = useState(false)
  const [shopsError, setShopsError] = useState<string | null>(null)
  const [selectedShopId, setSelectedShopId] = useState<number | null>(null)
  const [cart, setCart] = useState<Cart>(EMPTY_CART)
  const [cartLoading, setCartLoading] = useState(false)

  const refreshShops = useCallback(async () => {
    setShopsLoading(true)
    setShopsError(null)
    try {
      const list = await fetchShops()
      const normalized = list.map((s) => ({
        ...s,
        type: resolveShopType(s.shopId, s.type),
      }))
      setShops(normalized)
      setSelectedShopId((prev) => {
        if (prev != null && normalized.some((s) => s.shopId === prev)) return prev
        return preferShopId(loadLastShopId(), normalized)
      })
    } catch (e) {
      setShopsError(e instanceof Error ? e.message : '매장 목록을 불러오지 못했습니다')
      setShops([])
    } finally {
      setShopsLoading(false)
    }
  }, [])

  const selectedShop =
    shops.find((s) => s.shopId === selectedShopId) ?? null
  const canOrder = canOrderFromShop(selectedShop)

  const refreshCart = useCallback(async () => {
    if (selectedShopId == null || !canOrderFromShop(
      shops.find((s) => s.shopId === selectedShopId) ?? {
        shopId: selectedShopId,
        type: resolveShopType(selectedShopId),
        name: '',
        open: false,
      },
    )) {
      setCart(EMPTY_CART)
      return
    }
    setCartLoading(true)
    try {
      const next = await fetchCart(selectedShopId)
      setCart(next)
    } catch (e) {
      // Keep previous cart only on soft failures; clear when unreadable
      console.warn('cart refresh failed', e)
      setCart(EMPTY_CART)
    } finally {
      setCartLoading(false)
    }
  }, [selectedShopId, shops])

  useEffect(() => {
    void refreshShops()
  }, [refreshShops])

  useEffect(() => {
    void refreshCart()
  }, [refreshCart])

  const selectShop = useCallback((shopId: number) => {
    setSelectedShopId(shopId)
    saveLastShopId(shopId)
  }, [])

  const cartTotal = cartGrandTotal(cart.items)
  const cartCount = cartItemCount(cart.items)

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
      refreshCart,
      canOrder,
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
      refreshCart,
      canOrder,
    ],
  )

  return <ShopContext.Provider value={value}>{children}</ShopContext.Provider>
}

export function useShop(): ShopContextValue {
  const ctx = useContext(ShopContext)
  if (!ctx) throw new Error('useShop must be used within ShopProvider')
  return ctx
}
