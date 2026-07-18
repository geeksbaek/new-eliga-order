import { describe, expect, it } from 'vitest'
import {
  dishMatchesPrefs,
  extractFoodNamesFromPeriods,
  isUsableFoodName,
  normalizeFoodName,
  parseOriginFoodLines,
  sortDishesByPref,
} from './dining-prefs'
import type { DiningPeriod } from './types'
import type { GroupedDiningDish } from './dining-group'

describe('dining-prefs', () => {
  it('normalizes whitespace, case, brackets, and tags', () => {
    expect(normalizeFoodName('  제육  볶음  ')).toBe('제육 볶음')
    expect(normalizeFoodName('Americano (HOT)')).toBe('americano')
    expect(normalizeFoodName('[밸런스바이츠]차돌배추찜')).toBe('차돌배추찜')
    expect(normalizeFoodName('【이벤트】된장찌개(2인분)')).toBe('된장찌개')
    expect(normalizeFoodName('김밥*과일토핑샐러드')).toBe('김밥')
    expect(normalizeFoodName('Ａｍｅｒｉｃａｎｏ')).toBe('americano')
    expect(isUsableFoodName('Side 3 Pick')).toBe(false)
    expect(isUsableFoodName('제육볶음')).toBe(true)
  })

  it('parses 반찬 lines from [원산지] information block', () => {
    const info = `[원산지]
얼큰돈내장국밥
병천순대찜*들깨초장
(돼지:국내산)
오미산적
부추무침
쌀밥
섞박지
(배추,고춧가루:국내산)

[알러지주의음식]
알류

[매운정도]
`
    expect(parseOriginFoodLines(info)).toEqual([
      '얼큰돈내장국밥',
      '병천순대찜',
      '들깨초장',
      '오미산적',
      '부추무침',
      '쌀밥',
      '섞박지',
    ])
  })

  it('extracts meal name + 원산지 반찬 into catalog', () => {
    const periods: DiningPeriod[] = [
      {
        time: '중식',
        startTime: '11:00',
        endTime: '14:00',
        courses: [
          {
            name: '한식A',
            price: 0,
            soldOut: false,
            congestion: null,
            origin: '',
            menus: [
              {
                name: '얼큰돈내장국밥',
                calorie: 500,
                nutrition: '',
                information: `[원산지]
얼큰돈내장국밥
병천순대찜*들깨초장
(돼지:국내산)
부추무침
쌀밥
섞박지

[알러지주의음식]
`,
                imageUrl: 'x.jpg',
                soldOut: false,
              },
            ],
          },
        ],
      },
    ]
    const names = extractFoodNamesFromPeriods(periods)
    expect(names).toContain('얼큰돈내장국밥')
    expect(names).toContain('병천순대찜')
    expect(names).toContain('들깨초장')
    expect(names).toContain('부추무침')
    expect(names).toContain('쌀밥')
    expect(names).toContain('섞박지')
  })

  it('matches prefs from 원산지 반찬 on the dish', () => {
    const dish = {
      name: '얼큰돈내장국밥',
      sideDishes: [] as string[],
      information: `[원산지]
얼큰돈내장국밥
부추무침
쌀밥
섞박지
`,
    }
    expect(dishMatchesPrefs(dish, new Set(['부추무침']))).toBe(true)
    expect(dishMatchesPrefs(dish, new Set(['된장찌개']))).toBe(false)
    expect(
      dishMatchesPrefs(
        { name: '[이벤트]백반', sideDishes: [], information: '' },
        new Set(['백반']),
      ),
    ).toBe(true)
  })

  it('sorts preferred dishes first', () => {
    const dishes = [
      { key: 'a', name: 'A', sideDishes: [] },
      { key: 'b', name: 'B', sideDishes: ['선호반찬'] },
      { key: 'c', name: 'C', sideDishes: [] },
    ] as GroupedDiningDish[]
    const sorted = sortDishesByPref(dishes, new Set(['선호반찬']))
    expect(sorted[0].key).toBe('b')
  })
})
