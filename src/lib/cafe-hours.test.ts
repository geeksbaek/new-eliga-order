import { describe, expect, it } from 'vitest'
import {
  evaluateCafeHours,
  formatHoursRange,
  mapCafeSalesPlan,
  parseTimeToMinutes,
  type CafeSalesPlan,
} from './cafe-hours'

const basePlan = (over: Partial<CafeSalesPlan> = {}): CafeSalesPlan => ({
  shopId: 5,
  open: false,
  nowBreak: false,
  nowLastOrder: false,
  autoOnOff: true,
  autoOpenTime: '09:00:00',
  autoCloseTime: '19:00:00',
  lastOrderUse: false,
  lastOrderTime: null,
  useBreakTime: false,
  openDays: ['MON', 'TUE', 'WED', 'THU', 'FRI'],
  pauseOrder: false,
  ...over,
})

describe('cafe-hours', () => {
  it('parses HH:mm:ss to minutes', () => {
    expect(parseTimeToMinutes('09:00:00')).toBe(9 * 60)
    expect(parseTimeToMinutes('19:30')).toBe(19 * 60 + 30)
    expect(parseTimeToMinutes('')).toBeNull()
  })

  it('formats hour range', () => {
    expect(formatHoursRange('09:00:00', '19:00:00')).toBe('09:00–19:00')
    expect(formatHoursRange('11:00:00', '14:00:00')).toBe('11:00–14:00')
  })

  it('maps API sales-plan content', () => {
    const plan = mapCafeSalesPlan({
      content: {
        shopId: 3,
        openYn: false,
        nowBreakTimeYn: false,
        nowLastOrderYn: false,
        autoOnOffYn: true,
        autoOpenTime: '11:00:00',
        autoCloseTime: '14:00:00',
        lastOrderUseYn: false,
        lastOrderTime: '17:50:00',
        useBreakTimeYn: false,
        openDay: ['MON', 'TUE', 'WED', 'FRI', 'THU'],
        pauseOrderYn: false,
      },
    })
    expect(plan?.shopId).toBe(3)
    expect(plan?.open).toBe(false)
    expect(plan?.autoOpenTime).toBe('11:00:00')
    expect(plan?.openDays).toContain('MON')
    expect(plan?.openDays).toHaveLength(5)
  })

  it('blocks when pause or break', () => {
    expect(evaluateCafeHours(basePlan({ open: true, pauseOrder: true })).orderable).toBe(
      false,
    )
    expect(
      evaluateCafeHours(basePlan({ open: true, nowBreak: true })).reason,
    ).toBe('break')
  })

  it('allows when openYn true', () => {
    const st = evaluateCafeHours(basePlan({ open: true }))
    expect(st.orderable).toBe(true)
    expect(st.reason).toBe('open')
    expect(st.hoursLabel).toBe('09:00–19:00')
  })

  it('blocks when openYn false', () => {
    const st = evaluateCafeHours(basePlan({ open: false }))
    expect(st.orderable).toBe(false)
    expect(st.reason).toBe('closed')
    expect(st.message).toContain('09:00–19:00')
  })

  it('marks closed day when not in openDay', () => {
    // 2026-07-18 is Saturday
    const sat = new Date('2026-07-18T12:00:00+09:00')
    const st = evaluateCafeHours(
      basePlan({ open: false, openDays: ['MON', 'TUE', 'WED', 'THU', 'FRI'] }),
      sat,
    )
    expect(st.reason).toBe('closed_day')
    expect(st.orderable).toBe(false)
  })

  it('unknown plan is not orderable', () => {
    expect(evaluateCafeHours(null).orderable).toBe(false)
    expect(evaluateCafeHours(null).reason).toBe('unknown')
  })
})
