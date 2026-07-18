import { describe, expect, it } from 'vitest'
import {
  defaultCartOptions,
  defaultSelections,
  hasCompleteSingleDefaults,
} from './menu-options'
import type { GoodsVariant } from './types'

const americano: GoodsVariant = {
  goodsId: 568,
  name: '아메리카노 R HOT',
  displayName: 'HOT',
  price: 500,
  soldOut: false,
  description: null,
  calorie: null,
  nutrition: null,
  options: [
    {
      optionId: 40,
      name: '컵',
      multiSelect: false,
      menus: [
        { menuId: 68, name: '일회용컵', price: 0 },
        { menuId: 69, name: '머그잔', price: 0 },
        { menuId: 70, name: '텀블러', price: 0 },
      ],
    },
    {
      optionId: 39,
      name: '샷추가',
      multiSelect: true,
      menus: [
        { menuId: 66, name: '연하게', price: 0 },
        { menuId: 67, name: '샷추가', price: 300 },
      ],
    },
  ],
}

describe('defaultSelections / defaultCartOptions', () => {
  it('selects first cup option and leaves exclusive shot multi empty', () => {
    const sel = defaultSelections(americano)
    expect(sel[40]).toEqual([68])
    expect(sel[39]).toEqual([])
    const cart = defaultCartOptions(americano)
    expect(cart).toEqual([{ optionId: 40, menuIds: [68] }])
    expect(hasCompleteSingleDefaults(americano)).toBe(true)
  })

  it('selects all notice menus for bakery multi group', () => {
    const bakery: GoodsVariant = {
      ...americano,
      goodsId: 300,
      options: [
        {
          optionId: 46,
          name: '알림사항',
          multiSelect: true,
          menus: [
            { menuId: 80, name: '※베이커리', price: 0 },
            { menuId: 457, name: '※10분', price: 0 },
          ],
        },
      ],
    }
    expect(defaultSelections(bakery)[46]).toEqual([80, 457])
    expect(defaultCartOptions(bakery)).toHaveLength(1)
  })
})
