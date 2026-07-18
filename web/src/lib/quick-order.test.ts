import { describe, expect, it } from 'vitest'
import {
  assertQuickOrderCartIsolated,
  cartNeedsIsolation,
  isQuickOrderCartIsolated,
} from './quick-order'
import type { CartItem } from './types'

function item(
  partial: Partial<CartItem> & Pick<CartItem, 'cartItemId' | 'goodsId' | 'qty'>,
): CartItem {
  return {
    name: partial.name ?? `g${partial.goodsId}`,
    price: partial.price ?? 1000,
    options: partial.options ?? [],
    thumbnailUrl: null,
    ...partial,
  }
}

describe('quick-order isolation', () => {
  it('accepts a single matching line', () => {
    const cart = { items: [item({ cartItemId: 1, goodsId: 568, qty: 1 })] }
    expect(() =>
      assertQuickOrderCartIsolated(cart, { goodsId: 568, qty: 1 }),
    ).not.toThrow()
    expect(isQuickOrderCartIsolated(cart, { goodsId: 568 })).toBe(true)
  })

  it('rejects empty cart, extra lines, wrong goods, wrong qty', () => {
    expect(() =>
      assertQuickOrderCartIsolated({ items: [] }, { goodsId: 1 }),
    ).toThrow(/비어/)

    expect(() =>
      assertQuickOrderCartIsolated(
        {
          items: [
            item({ cartItemId: 1, goodsId: 1, qty: 1 }),
            item({ cartItemId: 2, goodsId: 2, qty: 1 }),
          ],
        },
        { goodsId: 1 },
      ),
    ).toThrow(/함께 결제/)

    expect(() =>
      assertQuickOrderCartIsolated(
        { items: [item({ cartItemId: 1, goodsId: 99, qty: 1 })] },
        { goodsId: 1 },
      ),
    ).toThrow(/일치하지/)

    expect(() =>
      assertQuickOrderCartIsolated(
        { items: [item({ cartItemId: 1, goodsId: 1, qty: 2 })] },
        { goodsId: 1, qty: 1 },
      ),
    ).toThrow(/수량/)
  })

  it('detects when isolation is needed before replace', () => {
    expect(cartNeedsIsolation([], 568)).toBe(false)
    expect(
      cartNeedsIsolation([item({ cartItemId: 1, goodsId: 568, qty: 1 })], 568),
    ).toBe(false)
    expect(
      cartNeedsIsolation([item({ cartItemId: 1, goodsId: 568, qty: 2 })], 568),
    ).toBe(true)
    expect(
      cartNeedsIsolation(
        [
          item({ cartItemId: 1, goodsId: 1, qty: 1 }),
          item({ cartItemId: 2, goodsId: 2, qty: 1 }),
        ],
        568,
      ),
    ).toBe(true)
  })
})
