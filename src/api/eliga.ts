/**
 * High-level Eliga Order API surface used by the UI.
 * Paths align with eliga-api.sh commands.
 */
import { apiRequest, BRAND_CODE, signIn as clientSignIn } from './client'
import {
  hiddenCategoryIds,
  mapCafeCategories,
  mapCafeMenu,
  mapCafeMenuDetail,
  mapCafeQuickItems,
  mapCart,
  mapDiningMenu,
  mapOrderHistory,
  mapPaymentReasons,
  mapShops,
} from '../lib/mappers'
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

export async function fetchCafeCategories(shopId: number): Promise<CafeCategory[]> {
  const raw = await apiRequest(`/goods/category?shopId=${shopId}`)
  return mapCafeCategories(raw)
}

export async function fetchCafeMenu(
  shopId: number,
  categoryId?: number,
): Promise<CafeMenuItem[]> {
  const cats = await fetchCafeCategories(shopId)
  const hidden = hiddenCategoryIds(cats)
  const params = new URLSearchParams({ shopId: String(shopId) })
  if (categoryId != null) params.set('categoryId', String(categoryId))
  const raw = await apiRequest(`/goods/display?${params}`)
  return mapCafeMenu(raw, hidden)
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
  const raw = await apiRequest(`/goods/order/recent/${shopId}`)
  return mapCafeQuickItems(raw)
}

export async function fetchPopularOrders(
  shopId: number,
): Promise<CafeQuickItem[]> {
  const raw = await apiRequest(`/goods/order/popular/${shopId}`)
  return mapCafeQuickItems(raw)
}

export async function fetchCustomerMe(): Promise<unknown> {
  return apiRequest('/customer/me')
}
