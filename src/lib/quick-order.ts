/**
 * Quick order (1 cup) isolation helpers.
 *
 * Eliga cafe checkout always goes through POST /goods/order with cartId +
 * goodsCartItemId lines. There is no cart-less direct-order API in the path
 * this app uses. To sell exactly one drink without co-paying existing cart
 * lines we:
 *   1) snapshot current cart lines (restorable goodsId/qty/options)
 *   2) clear the cart
 *   3) add only the target line
 *   4) assert isolation before confirm / placeOrder
 *   5) restore snapshot if the user abandons checkout
 */
import type { Cart, CartItem, SelectedOption } from './types'

export type StashedCartLine = {
  goodsId: number
  qty: number
  options: SelectedOption[]
}

export type QuickOrderSession = {
  shopId: number
  /** goodsId that must be the sole cart line at checkout */
  expectedGoodsId: number
  expectedQty: number
  stashed: StashedCartLine[]
  menuName: string
  createdAt: number
}

const SESSION_KEY = 'eliga.quickOrder.session'

export function saveQuickOrderSession(session: QuickOrderSession): void {
  try {
    sessionStorage.setItem(SESSION_KEY, JSON.stringify(session))
  } catch {
    /* ignore quota / private mode */
  }
}

export function loadQuickOrderSession(): QuickOrderSession | null {
  try {
    const raw = sessionStorage.getItem(SESSION_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as QuickOrderSession
    if (
      !parsed ||
      typeof parsed.shopId !== 'number' ||
      typeof parsed.expectedGoodsId !== 'number' ||
      !Array.isArray(parsed.stashed)
    ) {
      return null
    }
    return {
      shopId: parsed.shopId,
      expectedGoodsId: parsed.expectedGoodsId,
      expectedQty: Number(parsed.expectedQty) || 1,
      stashed: parsed.stashed,
      menuName: String(parsed.menuName ?? ''),
      createdAt: Number(parsed.createdAt) || Date.now(),
    }
  } catch {
    return null
  }
}

export function clearQuickOrderSession(): void {
  try {
    sessionStorage.removeItem(SESSION_KEY)
  } catch {
    /* ignore */
  }
}

/**
 * Hard gate: cart must contain exactly the quick-order line.
 * Call right before building the order payload.
 */
export function assertQuickOrderCartIsolated(
  cart: Pick<Cart, 'items'>,
  expected: { goodsId: number; qty?: number },
): void {
  const wantQty = expected.qty ?? 1
  const items = cart.items ?? []
  if (items.length === 0) {
    throw new Error('바로 주문 장바구니가 비어 있습니다')
  }
  if (items.length !== 1) {
    throw new Error(
      `바로 주문은 다른 장바구니 항목과 함께 결제할 수 없습니다 (현재 ${items.length}개)`,
    )
  }
  const only = items[0]
  if (only.goodsId !== expected.goodsId) {
    throw new Error('바로 주문 대상 메뉴와 장바구니가 일치하지 않습니다')
  }
  if (only.qty !== wantQty) {
    throw new Error(
      `바로 주문 수량이 올바르지 않습니다 (기대 ${wantQty}, 실제 ${only.qty})`,
    )
  }
}

/** Soft check for UI banners / disable state. */
export function isQuickOrderCartIsolated(
  cart: Pick<Cart, 'items'>,
  expected: { goodsId: number; qty?: number },
): boolean {
  try {
    assertQuickOrderCartIsolated(cart, expected)
    return true
  } catch {
    return false
  }
}

/**
 * Pure: given current cart items + the line we are about to order alone,
 * describe whether isolation is needed (existing foreign lines).
 */
export function cartNeedsIsolation(
  items: CartItem[],
  targetGoodsId: number,
): boolean {
  if (!items.length) return false
  if (items.length > 1) return true
  const only = items[0]
  return only.goodsId !== targetGoodsId || only.qty !== 1
}
