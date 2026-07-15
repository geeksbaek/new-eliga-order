/**
 * High-level Eliga Order API surface used by the UI.
 * Paths align with eliga-api.sh commands.
 */
import { apiRequest, BRAND_CODE, signIn as clientSignIn } from './client'
import {
  mapCafeSalesPlan,
  type CafeSalesPlan,
} from '../lib/cafe-hours'
import {
  hiddenCategoryIds,
  mapCafeCategories,
  mapCafeMenu,
  mapCafeMenuDetail,
  mapCafeQuickItems,
  mapCart,
  mapCartRestoreLines,
  mapDiningMenu,
  mapOrderHistory,
  mapPaymentReasons,
  mapShops,
} from '../lib/mappers'
import {
  assertQuickOrderCartIsolated,
  type StashedCartLine,
} from '../lib/quick-order'
import { inflight } from '../lib/inflight'
import {
  buildCartAddBody,
  buildCartDeleteBody,
  buildCartQuantityBody,
  buildOrderPayload,
} from '../lib/order-payload'
import { todayISODate } from '../lib/format'
import type {
  CafeCategory,
  CafeMenuItem,
  CafeQuickItem,
  Cart,
  MenuDetail,
  DiningPeriod,
  OrderHistoryView,
  OrderPayload,
  PaymentReason,
  SelectedOption,
  Shop,
  CartItem,
} from '../lib/types'

export { BRAND_CODE }

export async function login(userId: string, password: string) {
  return clientSignIn(userId, password)
}

export async function fetchShops(): Promise<Shop[]> {
  const raw = await apiRequest('/shop/me')
  return mapShops(raw)
}

export async function fetchShopInfo(shopId: number): Promise<unknown> {
  return apiRequest(`/shop/${shopId}`)
}

/** Per-cafe sales plan (openYn, auto open/close, openDay, pause/break). */
export async function fetchCafeSalesPlan(shopId: number): Promise<CafeSalesPlan | null> {
  return inflight(`cafe:plan:${shopId}`, async () => {
    const raw = await apiRequest(`/sales-plan/cafe/${shopId}`)
    return mapCafeSalesPlan(raw, shopId)
  })
}

export async function fetchCafeCategories(shopId: number): Promise<CafeCategory[]> {
  return inflight(`cafe:cats:${shopId}`, async () => {
    const raw = await apiRequest(`/goods/category?shopId=${shopId}`)
    return mapCafeCategories(raw)
  })
}

/**
 * Full (or category) cafe menu. Categories + display load in parallel;
 * concurrent callers for the same shop/cat share one in-flight request.
 */
export async function fetchCafeMenu(
  shopId: number,
  categoryId?: number,
): Promise<CafeMenuItem[]> {
  const catKey = categoryId == null ? 'all' : String(categoryId)
  return inflight(`cafe:menu:${shopId}:${catKey}`, async () => {
    const params = new URLSearchParams({ shopId: String(shopId) })
    if (categoryId != null) params.set('categoryId', String(categoryId))
    // Was sequential (cats → display); parallel cuts first-paint wait roughly in half.
    const [cats, raw] = await Promise.all([
      fetchCafeCategories(shopId),
      apiRequest(`/goods/display?${params}`),
    ])
    return mapCafeMenu(raw, hiddenCategoryIds(cats))
  })
}

export async function fetchCafeMenuDetail(displayId: number): Promise<MenuDetail> {
  const raw = await apiRequest(`/goods/display/${displayId}`)
  return mapCafeMenuDetail(raw)
}

export async function fetchDiningMenu(
  shopId: number,
  date: string = todayISODate(),
): Promise<DiningPeriod[]> {
  const raw = await apiRequest(
    `/meal/operation-times-and-courses?shopId=${shopId}&startDate=${date}&endDate=${date}`,
  )
  return mapDiningMenu(raw)
}

/** Multi-day cafeteria menu (for preference catalog). */
export async function fetchDiningMenuRange(
  shopId: number,
  startDate: string,
  endDate: string,
): Promise<DiningPeriod[]> {
  return inflight(
    `dining:range:${shopId}:${startDate}:${endDate}`,
    async () => {
      const raw = await apiRequest(
        `/meal/operation-times-and-courses?shopId=${shopId}&startDate=${startDate}&endDate=${endDate}`,
      )
      return mapDiningMenu(raw)
    },
  )
}

export async function fetchCart(shopId: number): Promise<Cart> {
  const raw = await apiRequest(
    `/goods/cart?shopId=${shopId}&cartType=GENERAL`,
  )
  return mapCart(raw)
}

export async function addToCart(params: {
  shopId: number
  goodsId: number
  qty?: number
  options?: SelectedOption[]
}): Promise<unknown> {
  const body = buildCartAddBody(params)
  return apiRequest('/goods/cart', { method: 'POST', body })
}

export async function updateCartQuantity(params: {
  cartId: number
  cartItemId: number
  goodsQty: number
}): Promise<unknown> {
  const body = buildCartQuantityBody(params)
  return apiRequest('/goods/cart/quantity', { method: 'PUT', body })
}

export async function deleteCartItems(params: {
  cartId: number
  cartItemIds: number[]
}): Promise<unknown> {
  const body = buildCartDeleteBody(params)
  return apiRequest('/goods/cart/item', { method: 'DELETE', body })
}

/**
 * Clear every line in a shop cart (no-op when empty).
 * Prefer item-delete over DELETE /goods/cart/{id} — item path is what the
 * production skill uses and is known-good.
 */
export async function clearCart(shopId: number): Promise<Cart> {
  const cart = await fetchCart(shopId)
  if (cart.cartId != null && cart.items.length > 0) {
    await deleteCartItems({
      cartId: cart.cartId,
      cartItemIds: cart.items.map((i) => i.cartItemId),
    })
  }
  return fetchCart(shopId)
}

/**
 * Isolate checkout to a single goods line:
 * snapshot → clear → add qty 1 → re-fetch and hard-assert isolation.
 *
 * There is no cart-less order API; this is the only safe way to guarantee
 * existing cart lines are never co-paid with a "바로 주문" cup.
 */
export async function prepareIsolatedQuickOrder(params: {
  shopId: number
  goodsId: number
  options?: SelectedOption[]
}): Promise<{ cart: Cart; stashed: StashedCartLine[] }> {
  const raw = await apiRequest(
    `/goods/cart?shopId=${params.shopId}&cartType=GENERAL`,
  )
  const stashed = mapCartRestoreLines(raw)
  const before = mapCart(raw)

  if (before.cartId != null && before.items.length > 0) {
    await deleteCartItems({
      cartId: before.cartId,
      cartItemIds: before.items.map((i) => i.cartItemId),
    })
  }

  await addToCart({
    shopId: params.shopId,
    goodsId: params.goodsId,
    qty: 1,
    options: params.options ?? [],
  })

  const cart = await fetchCart(params.shopId)
  assertQuickOrderCartIsolated(cart, {
    goodsId: params.goodsId,
    qty: 1,
  })
  return { cart, stashed }
}

/** Put previously stashed lines back after an abandoned quick order. */
export async function restoreStashedCart(
  shopId: number,
  stashed: StashedCartLine[],
): Promise<Cart> {
  await clearCart(shopId)
  for (const line of stashed) {
    if (!line.goodsId || line.qty <= 0) continue
    await addToCart({
      shopId,
      goodsId: line.goodsId,
      qty: line.qty,
      options: line.options,
    })
  }
  return fetchCart(shopId)
}

export async function fetchPaymentReasons(shopId: number): Promise<PaymentReason[]> {
  const raw = await apiRequest(`/payment/reason?shopId=${shopId}`)
  return mapPaymentReasons(raw)
}

export async function placeOrder(payload: OrderPayload): Promise<unknown> {
  return apiRequest('/goods/order', { method: 'POST', body: payload })
}

export function composeOrder(params: {
  shopId: number
  cartId: number
  paymentReasonId: number
  items: CartItem[]
}): OrderPayload {
  return buildOrderPayload(params)
}

export async function fetchOrderStatus(orderId: string | number): Promise<unknown> {
  return apiRequest(`/goods/order/status/${orderId}`)
}

export async function fetchOrderHistory(
  shopId?: number,
): Promise<OrderHistoryView[]> {
  // Backend NPEs when searchStartDate is null — always send a range.
  const end = todayISODate()
  const start = new Date()
  start.setMonth(start.getMonth() - 3)
  const params = new URLSearchParams({
    searchStartDate: todayISODate(start),
    searchEndDate: end,
  })
  if (shopId != null) params.set('shopId', String(shopId))
  const raw = await apiRequest(`/order/history?${params}`)
  return mapOrderHistory(raw)
}

export async function fetchRecentOrders(
  shopId: number,
): Promise<CafeQuickItem[]> {
  return inflight(`cafe:recent:${shopId}`, async () => {
    const raw = await apiRequest(`/goods/order/recent/${shopId}`)
    return mapCafeQuickItems(raw)
  })
}

export async function fetchPopularOrders(
  shopId: number,
): Promise<CafeQuickItem[]> {
  return inflight(`cafe:popular:${shopId}`, async () => {
    const raw = await apiRequest(`/goods/order/popular/${shopId}`)
    return mapCafeQuickItems(raw)
  })
}

export async function fetchCustomerMe(): Promise<unknown> {
  return apiRequest('/customer/me')
}
