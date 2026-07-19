import { describe, expect, it } from 'vitest'
import {
  cleanNotifyDishName,
  defaultNotificationPrefs,
  findPeriodForSlot,
  fitMenuTitle,
  formatMenuBody,
  minutesOfDay,
  normalizeTime,
  shouldFireMeal,
  type NotificationPrefs,
} from './meal-notify'
import type { DiningCourse, DiningPeriod } from './types'

function course(name: string, menuName: string): DiningCourse {
  return {
    name,
    price: 8000,
    soldOut: false,
    congestion: 'SMOOTH',
    origin: '',
    menus: [
      {
        name: menuName,
        calorie: 500,
        nutrition: '',
        information: '',
        imageUrl: null,
        soldOut: false,
      },
    ],
  }
}

const samplePeriods: DiningPeriod[] = [
  {
    time: '조식',
    startTime: '07:30:00',
    endTime: '09:00:00',
    courses: [course('한식', '죽')],
  },
  {
    time: '중식',
    startTime: '11:00:00',
    endTime: '14:00:00',
    courses: [course('한식A', '제육볶음'), course('팝업', '파스타')],
  },
  {
    time: '석식',
    startTime: '18:00:00',
    endTime: '20:00:00',
    courses: [],
  },
]

describe('normalizeTime', () => {
  it('pads hours', () => {
    expect(normalizeTime('9:05')).toBe('09:05')
    expect(normalizeTime('10:40')).toBe('10:40')
  })
})

describe('findPeriodForSlot', () => {
  it('matches Korean meal labels', () => {
    expect(findPeriodForSlot(samplePeriods, 'lunch')?.time).toBe('중식')
    expect(findPeriodForSlot(samplePeriods, 'dinner')?.time).toBe('석식')
    expect(findPeriodForSlot(samplePeriods, 'breakfast')?.time).toBe('조식')
  })
})

describe('cleanNotifyDishName', () => {
  it('strips bracket tags that break mid-title ellipsis', () => {
    expect(cleanNotifyDishName('곤드레나물밥 [밸런스바이츠]')).toBe(
      '곤드레나물밥',
    )
    expect(cleanNotifyDishName('미역국(HOT)')).toBe('미역국')
  })
})

describe('fitMenuTitle', () => {
  it('keeps meal prefix and at most two cleaned dishes', () => {
    const title = fitMenuTitle(['제육볶음', '파스타', '미역국'], {
      prefix: '중식',
      maxNames: 2,
    })
    expect(title.startsWith('중식 · ')).toBe(true)
    expect(title).toContain('제육볶음')
    expect(title).toMatch(/외 1/)
    expect(title).not.toMatch(/엘리가|http|vercel|new-eliga/i)
  })

  it('strips tags before fitting', () => {
    const title = fitMenuTitle(['곤드레나물밥 [밸런스바이츠]', '된장찌개'], {
      prefix: '중식',
      maxNames: 2,
      maxLen: 40,
    })
    expect(title).toContain('곤드레나물밥')
    expect(title).not.toContain('밸런스')
    expect(title).not.toContain('[')
  })
})

describe('formatMenuBody', () => {
  it('puts meal only in title and full menu only in body (no overlap)', () => {
    const period = findPeriodForSlot(samplePeriods, 'lunch')
    const { title, body } = formatMenuBody(period, '중식')
    expect(title).toBe('오늘 중식')
    expect(title).not.toMatch(/제육|파스타|엘리가|vercel|new-eliga/i)
    expect(body).toContain('한식A · 제육볶음')
    expect(body).toContain('파스타')
    for (const dish of ['제육볶음', '파스타']) {
      expect(title.includes(dish)).toBe(false)
      expect(body.includes(dish)).toBe(true)
    }
  })

  it('merges the same dish across 한식B / 팝업A into one body line', () => {
    const period: DiningPeriod = {
      time: '중식',
      startTime: '11:00:00',
      endTime: '14:00:00',
      courses: [
        course('한식B', '닭목살간장구이'),
        course('팝업A', '닭목살간장구이'),
        course('한식A', '미역국 [밸런스바이츠]'),
        course('팝업B', '미역국'),
      ],
    }
    const { body } = formatMenuBody(period, '중식')
    const lines = body.split('\n')
    // 닭목살: exact-name merge via groupDiningDishes
    expect(lines.filter((l) => l.includes('닭목살간장구이'))).toHaveLength(1)
    expect(body).toContain('한식B · 팝업A · 닭목살간장구이')
    // 미역국: tag-stripped second-pass merge
    expect(lines.filter((l) => l.includes('미역국'))).toHaveLength(1)
    expect(body).toMatch(/한식A · 팝업B · 미역국|팝업B · 한식A · 미역국/)
    expect(body).not.toContain('[밸런스')
  })

  it('handles empty period without branding', () => {
    const { title, body } = formatMenuBody(null, '석식')
    expect(title).toBe('오늘 석식')
    expect(body).toMatch(/없습니다/)
    expect(title).not.toMatch(/엘리가/)
  })
})

describe('shouldFireMeal', () => {
  const prefs: NotificationPrefs = defaultNotificationPrefs()

  it('fires inside the window when enabled', () => {
    const now = new Date()
    now.setHours(10, 45, 0, 0)
    const p = {
      ...prefs,
      lastSent: {},
      meals: {
        ...prefs.meals,
        lunch: { enabled: true, time: '10:40' },
      },
    }
    expect(shouldFireMeal(p.meals.lunch, 'lunch', p, now)).toBe(true)
  })

  it('does not fire before scheduled time', () => {
    const now = new Date()
    now.setHours(10, 0, 0, 0)
    const p = {
      ...prefs,
      lastSent: {},
      meals: {
        ...prefs.meals,
        lunch: { enabled: true, time: '10:40' },
      },
    }
    expect(shouldFireMeal(p.meals.lunch, 'lunch', p, now)).toBe(false)
  })

  it('does not fire twice the same day', () => {
    const now = new Date()
    now.setHours(10, 45, 0, 0)
    const y = now.getFullYear()
    const m = String(now.getMonth() + 1).padStart(2, '0')
    const d = String(now.getDate()).padStart(2, '0')
    const day = `${y}-${m}-${d}`
    const p = {
      ...prefs,
      lastSent: { [`${day}:lunch`]: day },
      meals: {
        ...prefs.meals,
        lunch: { enabled: true, time: '10:40' },
      },
    }
    expect(shouldFireMeal(p.meals.lunch, 'lunch', p, now)).toBe(false)
  })
})

describe('minutesOfDay', () => {
  it('parses HH:mm', () => {
    expect(minutesOfDay('10:40')).toBe(10 * 60 + 40)
  })
})
