import { describe, expect, it } from 'vitest'
import {
  groupDiningDishes,
  isPeriodLive,
  periodMatchesQuery,
  periodSlug,
  pickBestPeriodIndex,
  timeToSeconds,
} from './dining-group'
import type { DiningCourse, DiningPeriod } from './types'

function course(
  name: string,
  menuName: string,
  extra?: Partial<DiningCourse> & { calorie?: number },
): DiningCourse {
  return {
    name,
    price: 8000,
    soldOut: false,
    congestion: extra?.congestion ?? 'SMOOTH',
    origin: extra?.origin ?? '국내산',
    menus: [
      {
        name: menuName,
        calorie: extra?.calorie ?? 900,
        nutrition: '',
        information: '',
        imageUrl: `img/${menuName}.jpg`,
        soldOut: false,
      },
    ],
  }
}

describe('groupDiningDishes', () => {
  it('merges same menu across courses and drops price concerns', () => {
    const courses = [
      course('한식A', '[초복특식]삼계탕', { congestion: 'NORMAL' }),
      course('팝업A', '[초복특식]삼계탕', { congestion: 'SMOOTH' }),
      course('한식B', '[초복특식]마늘보쌈'),
    ]
    const grouped = groupDiningDishes(courses)
    expect(grouped).toHaveLength(2)
    expect(grouped[0].name).toBe('[초복특식]삼계탕')
    expect(grouped[0].courseNames).toEqual(['한식A', '팝업A'])
    expect(grouped[0].congestion).toBe('NORMAL')
    expect(grouped[1].courseNames).toEqual(['한식B'])
  })

  it('keeps multi-menu takeout items as separate names', () => {
    const courses: DiningCourse[] = [
      {
        name: 'TAKE OUT',
        price: 8000,
        soldOut: false,
        congestion: 'SMOOTH',
        origin: '',
        menus: [
          {
            name: '김밥',
            calorie: 400,
            nutrition: '',
            information: '',
            imageUrl: null,
            soldOut: false,
          },
          {
            name: '샐러드',
            calorie: 300,
            nutrition: '',
            information: '',
            imageUrl: null,
            soldOut: false,
          },
        ],
      },
    ]
    const grouped = groupDiningDishes(courses)
    expect(grouped.map((g) => g.name)).toEqual(['김밥', '샐러드'])
    expect(grouped.every((g) => g.courseNames[0] === 'TAKE OUT')).toBe(true)
    expect(grouped.every((g) => g.sideDishes.length === 0)).toBe(true)
  })

  it('does not fold takeout items into 반찬 even if one has a photo', () => {
    const courses: DiningCourse[] = [
      {
        name: 'TAKE OUT',
        price: 8000,
        soldOut: false,
        congestion: 'SMOOTH',
        origin: '',
        menus: [
          {
            name: '치킨마요',
            calorie: 500,
            nutrition: '',
            information: '',
            imageUrl: 'img/chicken.jpg',
            soldOut: false,
          },
          {
            name: '참치마요',
            calorie: 480,
            nutrition: '',
            information: '',
            imageUrl: null,
            soldOut: false,
          },
          {
            name: '유부초밥',
            calorie: 300,
            nutrition: '',
            information: '',
            imageUrl: null,
            soldOut: false,
          },
        ],
      },
    ]
    const grouped = groupDiningDishes(courses)
    expect(grouped.map((g) => g.name)).toEqual([
      '치킨마요',
      '참치마요',
      '유부초밥',
    ])
    expect(grouped.every((g) => g.sideDishes.length === 0)).toBe(true)
  })

  it('attaches same-course 반찬 under the photo main dish', () => {
    const courses: DiningCourse[] = [
      {
        name: '한식A',
        price: 8000,
        soldOut: false,
        congestion: 'SMOOTH',
        origin: '국내산',
        menus: [
          {
            name: '제육볶음',
            calorie: 700,
            nutrition: '열량 700kcal',
            information: '배추김치, 미역국',
            imageUrl: 'img/jeyuk.jpg',
            soldOut: false,
          },
          {
            name: '시금치나물',
            calorie: null,
            nutrition: '',
            information: '',
            imageUrl: null,
            soldOut: false,
          },
          {
            name: '계란말이',
            calorie: null,
            nutrition: '',
            information: '',
            imageUrl: null,
            soldOut: false,
          },
        ],
      },
    ]
    const grouped = groupDiningDishes(courses)
    expect(grouped).toHaveLength(1)
    expect(grouped[0].name).toBe('제육볶음')
    expect(grouped[0].sideDishes).toEqual(['시금치나물', '계란말이'])
    expect(grouped[0].information).toContain('배추김치')
  })
})

const samplePeriods: DiningPeriod[] = [
  {
    time: '중식',
    startTime: '11:00:00',
    endTime: '14:00:00',
    courses: [],
  },
  {
    time: 'MORE BITE',
    startTime: '14:00:00',
    endTime: '14:15:00',
    courses: [],
  },
  {
    time: '석식',
    startTime: '18:00:00',
    endTime: '19:30:00',
    courses: [],
  },
]

describe('pickBestPeriodIndex', () => {
  it('parses time strings', () => {
    expect(timeToSeconds('11:00:00')).toBe(11 * 3600)
    expect(timeToSeconds('14:15')).toBe(14 * 3600 + 15 * 60)
  })

  it('selects live window during lunch', () => {
    const now = new Date('2026-07-15T12:30:00')
    expect(
      pickBestPeriodIndex(samplePeriods, {
        now,
        dateISO: '2026-07-15',
      }),
    ).toBe(0)
  })

  it('selects next upcoming between lunch and dinner', () => {
    const now = new Date('2026-07-15T16:00:00')
    expect(
      pickBestPeriodIndex(samplePeriods, {
        now,
        dateISO: '2026-07-15',
      }),
    ).toBe(2) // 석식 next
  })

  it('selects last period after dinner ends', () => {
    const now = new Date('2026-07-15T21:00:00')
    expect(
      pickBestPeriodIndex(samplePeriods, {
        now,
        dateISO: '2026-07-15',
      }),
    ).toBe(2)
  })

  it('selects first period before opening', () => {
    const now = new Date('2026-07-15T08:00:00')
    expect(
      pickBestPeriodIndex(samplePeriods, {
        now,
        dateISO: '2026-07-15',
      }),
    ).toBe(0)
  })

  it('defaults to lunch label on non-today dates', () => {
    const now = new Date('2026-07-15T20:00:00')
    expect(
      pickBestPeriodIndex(samplePeriods, {
        now,
        dateISO: '2026-07-16',
      }),
    ).toBe(0)
  })
})

describe('periodSlug / matches / live', () => {
  it('maps Korean meal labels to slugs', () => {
    expect(periodSlug({ time: '중식' })).toBe('lunch')
    expect(periodSlug({ time: '석식' })).toBe('dinner')
    expect(periodSlug({ time: '조식' })).toBe('breakfast')
  })

  it('matches query aliases', () => {
    expect(periodMatchesQuery({ time: '중식' }, 'lunch')).toBe(true)
    expect(periodMatchesQuery({ time: '중식' }, '중식')).toBe(true)
    expect(periodMatchesQuery({ time: '석식' }, 'dinner')).toBe(true)
    expect(periodMatchesQuery({ time: '중식' }, 'dinner')).toBe(false)
  })

  it('detects live service window', () => {
    const p = { startTime: '11:00:00', endTime: '14:00:00' }
    expect(isPeriodLive(p, new Date('2026-07-15T12:00:00'))).toBe(true)
    expect(isPeriodLive(p, new Date('2026-07-15T10:00:00'))).toBe(false)
  })
})
