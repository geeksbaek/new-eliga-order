import { describe, expect, it } from 'vitest'
import {
  cartGrandTotal,
  cartItemCount,
  lineTotal,
  optionExtrasTotal,
  unitPriceWithOptions,
} from './cart-math'
import type { GoodsOption, SelectedOption } from './types'

const options: GoodsOption[] = [
  {
    optionId: 40,
    name: '컵',
    multiSelect: false,
    menus: [
      { menuId: 68, name: '매장컵', price: 0 },
      { menuId: 69, name: '일회용', price: 0 },
    ],
  },
  {
    optionId: 41,
    name: '샷 추가',
    multiSelect: true,
    menus: [
      { menuId: 70, name: '샷 1', price: 500 },
      { menuId: 71, name: '샷 2', price: 1000 },
    ],
  },
]

describe('cart-math', () => {
  it('computes line total as price * qty', () => {
    expect(lineTotal({ price: 2000, qty: 3 })).toBe(6000)
    expect(lineTotal({ price: 0, qty: 5 })).toBe(0)
  })

  it('sums cart grand total from fixture-like cart items', () => {
    const items = [
      { price: 2000, qty: 1 },
      { price: 500, qty: 2 },
      { price: 3500, qty: 1 },
    ]
    expect(cartGrandTotal(items)).toBe(2000 + 1000 + 3500)
    expect(cartItemCount(items)).toBe(4)
  })

  it('adds option extras for selected menus', () => {
    const selected: SelectedOption[] = [
      { optionId: 40, menuId: 68 },
      { optionId: 41, menuIds: [70, 71] },
    ]
    expect(optionExtrasTotal(options, selected)).toBe(1500)
    expect(unitPriceWithOptions(500, options, selected)).toBe(2000)
  })
})
