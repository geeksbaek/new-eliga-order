import { describe, expect, it } from 'vitest'
import {
  baseMenuTitle,
  classifyTemp,
  needsTempPick,
  pickDefaultVariant,
  tempPickOptions,
} from './temp-variants'
import type { GoodsVariant } from './types'

function v(
  partial: Partial<GoodsVariant> & Pick<GoodsVariant, 'goodsId' | 'name'>,
): GoodsVariant {
  return {
    displayName: partial.displayName ?? '',
    price: partial.price ?? 500,
    soldOut: partial.soldOut ?? false,
    description: null,
    calorie: null,
    nutrition: null,
    thumbnailUrl: null,
    options: [],
    ...partial,
  }
}

describe('temp-variants', () => {
  it('classifies HOT / ICE from name and displayName', () => {
    expect(classifyTemp(v({ goodsId: 1, name: '아메리카노 R HOT', displayName: 'HOT' }))).toBe(
      'hot',
    )
    expect(classifyTemp(v({ goodsId: 2, name: '아메리카노 R ICE', displayName: 'ICE' }))).toBe(
      'ice',
    )
    expect(classifyTemp(v({ goodsId: 3, name: '아메리카노 ICED', displayName: 'ICED' }))).toBe(
      'ice',
    )
    expect(classifyTemp(v({ goodsId: 4, name: '쿠키', displayName: '' }))).toBe('other')
  })

  it('needs temp pick only when both HOT and ICE are available', () => {
    const both = [
      v({ goodsId: 1, name: '아메 HOT', displayName: 'HOT' }),
      v({ goodsId: 2, name: '아메 ICE', displayName: 'ICE' }),
    ]
    expect(needsTempPick(both)).toBe(true)
    expect(tempPickOptions(both)).toHaveLength(2)
    expect(tempPickOptions(both).map((o) => o.kind)).toEqual(['ice', 'hot'])

    const hotOnly = [v({ goodsId: 1, name: 'HOT', displayName: 'HOT' })]
    expect(needsTempPick(hotOnly)).toBe(false)

    const iceSoldOut = [
      v({ goodsId: 1, name: 'HOT', displayName: 'HOT' }),
      v({ goodsId: 2, name: 'ICE', displayName: 'ICE', soldOut: true }),
    ]
    expect(needsTempPick(iceSoldOut)).toBe(false)
  })

  it('picks preferred goodsId when available', () => {
    const variants = [
      v({ goodsId: 10, name: 'HOT', displayName: 'HOT' }),
      v({ goodsId: 20, name: 'ICE', displayName: 'ICE' }),
    ]
    expect(pickDefaultVariant(variants, 20)?.goodsId).toBe(20)
    expect(pickDefaultVariant(variants, 99)?.goodsId).toBe(10)
    expect(
      pickDefaultVariant(
        [
          v({ goodsId: 1, name: 'HOT', soldOut: true }),
          v({ goodsId: 2, name: 'ICE' }),
        ],
        1,
      )?.goodsId,
    ).toBe(2)
  })

  it('strips trailing temp from title', () => {
    expect(baseMenuTitle('아메리카노 R HOT')).toBe('아메리카노 R')
    expect(baseMenuTitle('라떼 ICE')).toBe('라떼')
  })
})
