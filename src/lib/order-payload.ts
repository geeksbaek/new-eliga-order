import { cartGrandTotal, lineTotal } from './cart-math'
import type {
  CartItem,
  CartAddItem,
  OrderPayload,
  OrderItemPayload,
  SelectedOption,
} from './types'

const BRAND_CODE = 'kakao'

/**
 * Build production order body used by eliga-api.sh (prefer script over api-reference.md).
 */
export function buildOrderPayload(params: {
  shopId: number
  cartId: number
  paymentReasonId: number
  items: CartItem[]
  deviceType?: 'MOBILE' | 'PC'
}): OrderPayload {
  const { shopId, cartId, paymentReasonId, items } = params
  if (!cartId) {
    throw new Error('cartId is required to place an order')
  }
  if (!paymentReasonId) {
    throw new Error('paymentReasonId is required for cafe orders')
  }
  if (!items.length) {
    throw new Error('orderItems must not be empty')
  }

  const orderItems: OrderItemPayload[] = items.map((item) => {
    const unit = Number(item.price) || 0
    const qty = Number(item.qty) || 0
    return {
      goodsId: item.goodsId,
      goodsQty: qty,
      salesPrice: lineTotal(item),
      unitPrice: unit,
      goodsCartItemId: item.cartItemId,
      goodsOrderItemOptions: [],
    }
  })

  const total = cartGrandTotal(items)

  return {
    deviceType: params.deviceType ?? 'MOBILE',
    orderType: 'AUTO',
    payType: 'INTERNAL',
    brandCode: BRAND_CODE,
    shopId,
    cartId,
    totalUnitPrice: total,
    totalSalesPrice: total,
    totalUsedPoint: 0,
    goodsOrderType: 'SHOP_PICKUP',
    paymentReasonId,
    orderItems,
  }
}

/**
 * Build cart-add API body (fmt.py cart-add-build / eliga-api.sh).
 */
export function buildCartAddBody(params: {
  shopId: number
  goodsId: number
  qty?: number
  options?: SelectedOption[]
}): Record<string, unknown> {
  const qty = params.qty ?? 1
  const cartOpts = (params.options ?? []).map((opt) => {
    const menuIds =
      opt.menuIds && opt.menuIds.length > 0
        ? opt.menuIds
        : opt.menuId != null
          ? [opt.menuId]
          : []
    return {
      goodsOptionId: opt.optionId,
      goodsCartItemOptionMenus: menuIds.map((mid) => ({
        goodsOptionMenuId: mid,
      })),
    }
  })

  return {
    shopId: params.shopId,
    cartType: 'GENERAL',
    generalCartId: null,
    goodsCartItems: [
      {
        goodsId: params.goodsId,
        goodsQty: qty,
        goodsCartItemOptions: cartOpts,
      },
    ],
  }
}

/** Batch cart-add bodies from simplified skill input. */
export function buildCartAddBodiesFromBatch(input: {
  shopId: number
  items: CartAddItem[]
}): Record<string, unknown>[] {
  return input.items.map((item) =>
    buildCartAddBody({
      shopId: input.shopId,
      goodsId: item.goodsId,
      qty: item.qty,
      options: item.options,
    }),
  )
}

export function buildCartQuantityBody(params: {
  cartId: number
  cartItemId: number
  goodsQty: number
}): Record<string, number> {
  return {
    cartId: params.cartId,
    cartItemId: params.cartItemId,
    goodsQty: params.goodsQty,
  }
}

export function buildCartDeleteBody(params: {
  cartId: number
  cartItemIds: number[]
}): { id: number; goodsCartItemIds: number[] } {
  return {
    id: params.cartId,
    goodsCartItemIds: params.cartItemIds,
  }
}

/** Prefer 개인결제 when present; otherwise first reason. */
export function pickDefaultPaymentReasonId(
  reasons: Array<{ id: number; reason: string }>,
): number | null {
  if (!reasons.length) return null
  const personal = reasons.find((r) =>
    /개인\s*결제|personal/i.test(r.reason),
  )
  return (personal ?? reasons[0]).id
}

/**
 * Explicit confirmation gate: order must only proceed when user confirmed.
 * Pure helper so UI and tests share the same rule.
 */
export function assertOrderConfirmed(confirmed: boolean): void {
  if (!confirmed) {
    throw new Error('주문을 실행하려면 최종 확인이 필요합니다')
  }
}
