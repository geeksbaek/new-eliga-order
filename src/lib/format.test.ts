import { describe, expect, it } from 'vitest'
import { calcPlanPrice, formatWon, localizeName, todayISODate } from './format'

describe('format helpers', () => {
  it('localizes ko/en name objects like fmt.py', () => {
    expect(localizeName({ ko: '아메리카노', en: 'Americano' })).toBe(
      '아메리카노',
    )
    expect(localizeName({ en: 'Only EN' })).toBe('Only EN')
    expect(localizeName('plain')).toBe('plain')
  })

  it('calculates NORMAL - IDCARD price from goodsPricePlans fixture', () => {
    const plans = [
      { payMethodType: 'NORMAL', price: 3000 },
      { payMethodType: 'IDCARD', price: 2500 },
    ]
    expect(calcPlanPrice(plans)).toBe(500)
    expect(
      calcPlanPrice(
        [
          { payMethodType: 'NORMAL', optionPrice: 1000 },
          { payMethodType: 'IDCARD', optionPrice: 0 },
        ],
        'optionPrice',
      ),
    ).toBe(1000)
  })

  it('formats won and date', () => {
    expect(formatWon(3500)).toBe('₩3,500')
    expect(todayISODate(new Date('2026-07-15T12:00:00'))).toBe('2026-07-15')
  })
})
