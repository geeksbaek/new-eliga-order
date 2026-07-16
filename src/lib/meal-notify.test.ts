import { describe, expect, it } from 'vitest'
import {
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

describe('fitMenuTitle', () => {
  it('joins dish names without app branding', () => {
    const title = fitMenuTitle(['제육볶음', '파스타', '미역국'])
    expect(title).toBe('제육볶음 · 파스타 · 미역국')
    expect(title).not.toMatch(/엘리가|http|vercel|new-eliga/i)
  })

  it('truncates with 외 N when over max length', () => {
    const title = fitMenuTitle(
      ['아주아주긴메뉴이름하나', '아주아주긴메뉴이름둘', '셋', '넷', '다섯'],
      30,
    )
    expect(title).toMatch(/외 \d+/)
    expect(title).not.toMatch(/엘리가/)
  })
})

describe('formatMenuBody', () => {
  it('puts dish names in title and courses in body', () => {
    const period = findPeriodForSlot(samplePeriods, 'lunch')
    const { title, body } = formatMenuBody(period, '중식')
    expect(title).toContain('제육볶음')
    expect(title).toContain('파스타')
    expect(title).not.toMatch(/엘리가오더|http|vercel/i)
    expect(body.startsWith('중식')).toBe(true)
    expect(body).toContain('제육볶음')
    expect(body).toContain('파스타')
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
