import { describe, expect, it } from 'vitest'
import {
  goodsQtyInCart,
  optimisticBumpGoods,
  optimisticRemoveLine,
  optimisticSetLineQty,
  reapplyPendingGoodsDeltas,
} from './cart-optimistic'
import type { Cart } from './types'

const empty: Cart = { cartId: 10, items: [] }

const withLine: Cart = {
  cartId: 10,
  items: [
    {
      cartItemId: 1,
      goodsId: 100,
      name: '아메리카노',
      qty: 2,
      price: 3000,
      options: [],
      thumbnailUrl: null,
    },
  ],
}

describe('optimisticBumpGoods', () => {
  it('adds a temp line on first +', () => {
    const next = optimisticBumpGoods(
      empty,
      { goodsId: 100, name: '아메리카노', price: 3000 },
      1,
    )
    expect(goodsQtyInCart(next, 100)).toBe(1)
    expect(next.items[0].cartItemId).toBeLessThan(0)
  })

  it('increments existing line', () => {
    const next = optimisticBumpGoods(
      withLine,
      { goodsId: 100, name: '아메리카노', price: 3000 },
      1,
    )
    expect(goodsQtyInCart(next, 100)).toBe(3)
  })

  it('removes line at zero', () => {
    const next = optimisticBumpGoods(
      withLine,
      { goodsId: 100, name: '아메리카노', price: 3000 },
      -2,
    )
    expect(next.items).toHaveLength(0)
  })
})

describe('optimisticSetLineQty', () => {
  it('updates qty and removes at 0', () => {
    expect(optimisticSetLineQty(withLine, 1, 5).items[0].qty).toBe(5)
    expect(optimisticRemoveLine(withLine, 1).items).toHaveLength(0)
  })
})

describe('reapplyPendingGoodsDeltas', () => {
  it('layers pending deltas on server cart', () => {
    const pending = new Map([[100, 2]])
    const names = new Map([[100, { name: '아메리카노', price: 3000 }]])
    const next = reapplyPendingGoodsDeltas(withLine, pending, names)
    expect(goodsQtyInCart(next, 100)).toBe(4)
  })
})
