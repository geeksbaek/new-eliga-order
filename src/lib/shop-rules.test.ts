import { describe, expect, it } from 'vitest'
import {
  CAFETERIA_SHOP_ID,
  DEFAULT_CAFE_SHOP_ID,
  canOrderFromShop,
  canViewDiningMenu,
  isCafeShop,
  isCafeteriaShop,
  preferShopId,
  soldOutBlocksOrder,
} from './shop-rules'

describe('shop-rules', () => {
  it('classifies cafe vs cafeteria', () => {
    expect(isCafeShop('CAFE')).toBe(true)
    expect(isCafeteriaShop('CAFETERIA')).toBe(true)
    expect(isCafeteriaShop('RESTAURANT')).toBe(true)
    expect(isCafeShop('CAFETERIA')).toBe(false)
  })

  it('allows order only for cafe shops', () => {
    expect(
      canOrderFromShop({ shopId: 5, type: 'CAFE' }),
    ).toBe(true)
    expect(
      canOrderFromShop({ shopId: CAFETERIA_SHOP_ID, type: 'CAFETERIA' }),
    ).toBe(false)
    expect(
      canOrderFromShop({ shopId: 7, type: 'CAFE' }),
    ).toBe(false)
    expect(canOrderFromShop(null)).toBe(false)
  })

  it('allows dining view for cafeteria', () => {
    expect(
      canViewDiningMenu({ shopId: 7, type: 'CAFETERIA' }),
    ).toBe(true)
    expect(
      canViewDiningMenu({ shopId: 5, type: 'CAFE' }),
    ).toBe(false)
  })

  it('blocks sold-out ordering', () => {
    expect(soldOutBlocksOrder(true)).toBe(true)
    expect(soldOutBlocksOrder(false)).toBe(false)
  })

  it('prefers last-used shop then default cafe 5', () => {
    const available = [{ shopId: 3 }, { shopId: 5 }, { shopId: 7 }]
    expect(preferShopId(3, available)).toBe(3)
    expect(preferShopId(99, available)).toBe(DEFAULT_CAFE_SHOP_ID)
    expect(preferShopId(null, [{ shopId: 4 }])).toBe(4)
  })
})
