/**
 * Cafe operating hours from `/sales-plan/cafe/{shopId}`.
 * Server openYn is authoritative for current open state; schedule fields
 * drive labels and client-side last-order / open-day messaging.
 */

export type CafeSalesPlan = {
  shopId: number
  open: boolean
  nowBreak: boolean
  nowLastOrder: boolean
  autoOnOff: boolean
  autoOpenTime: string | null
  autoCloseTime: string | null
  lastOrderUse: boolean
  lastOrderTime: string | null
  useBreakTime: boolean
  openDays: string[]
  pauseOrder: boolean
}

export type CafeHoursReason =
  | 'open'
  | 'closed'
  | 'break'
  | 'pause'
  | 'last_order_ended'
  | 'closed_day'
  | 'unknown'

export type CafeHoursStatus = {
  orderable: boolean
  reason: CafeHoursReason
  /** e.g. "09:00–19:00" */
  hoursLabel: string
  /** Short status for chips / header */
  statusLabel: string
  /** Full user-facing message */
  message: string
  plan: CafeSalesPlan | null
}

const DAY_CODES = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'] as const

function ynTrue(v: unknown): boolean {
  return v === true || v === 'Y' || v === 'y' || v === 1 || v === '1'
}

function asArray<T>(v: unknown): T[] {
  return Array.isArray(v) ? (v as T[]) : []
}

function contentOf(data: unknown): unknown {
  if (data && typeof data === 'object' && 'content' in data) {
    return (data as { content: unknown }).content
  }
  return data
}

/** "09:00:00" | "09:00" → minutes from midnight, or null */
export function parseTimeToMinutes(raw: string | null | undefined): number | null {
  if (raw == null) return null
  const s = String(raw).trim()
  if (!s) return null
  const m = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(s)
  if (!m) return null
  const h = Number(m[1])
  const min = Number(m[2])
  if (!Number.isFinite(h) || !Number.isFinite(min)) return null
  if (h < 0 || h > 23 || min < 0 || min > 59) return null
  return h * 60 + min
}

/** "09:00:00" → "09:00" */
export function formatHm(raw: string | null | undefined): string {
  if (raw == null || !String(raw).trim()) return ''
  const mins = parseTimeToMinutes(raw)
  if (mins == null) {
    const s = String(raw).trim()
    return s.length >= 5 ? s.slice(0, 5) : s
  }
  const h = Math.floor(mins / 60)
  const m = mins % 60
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`
}

export function formatHoursRange(
  open: string | null | undefined,
  close: string | null | undefined,
): string {
  const a = formatHm(open)
  const b = formatHm(close)
  if (a && b) return `${a}–${b}`
  if (a) return `${a}–`
  if (b) return `–${b}`
  return ''
}

function minutesNow(d: Date): number {
  return d.getHours() * 60 + d.getMinutes()
}

function dayCode(d: Date): string {
  return DAY_CODES[d.getDay()]
}

function isOpenDay(plan: CafeSalesPlan, d: Date): boolean {
  if (!plan.openDays.length) return true
  const code = dayCode(d)
  return plan.openDays.some((x) => String(x).toUpperCase() === code)
}

export function mapCafeSalesPlan(raw: unknown, shopIdFallback?: number): CafeSalesPlan | null {
  const content = contentOf(raw)
  if (!content || typeof content !== 'object') return null
  const o = content as Record<string, unknown>
  const shopId = Number(o.shopId ?? o.id ?? shopIdFallback)
  if (!Number.isFinite(shopId)) return null

  const openDays = asArray<unknown>(o.openDay)
    .map((d) => String(d).toUpperCase())
    .filter(Boolean)

  return {
    shopId,
    open: ynTrue(o.openYn),
    nowBreak: ynTrue(o.nowBreakTimeYn),
    nowLastOrder: ynTrue(o.nowLastOrderYn),
    autoOnOff: ynTrue(o.autoOnOffYn),
    autoOpenTime:
      typeof o.autoOpenTime === 'string' ? o.autoOpenTime : null,
    autoCloseTime:
      typeof o.autoCloseTime === 'string' ? o.autoCloseTime : null,
    lastOrderUse: ynTrue(o.lastOrderUseYn),
    lastOrderTime:
      typeof o.lastOrderTime === 'string' ? o.lastOrderTime : null,
    useBreakTime: ynTrue(o.useBreakTimeYn),
    openDays,
    pauseOrder: ynTrue(o.pauseOrderYn),
  }
}

function scheduleAllowsOrder(plan: CafeSalesPlan, now: Date): boolean {
  if (!isOpenDay(plan, now)) return false
  const openM = parseTimeToMinutes(plan.autoOpenTime)
  const closeM = parseTimeToMinutes(
    plan.lastOrderUse && plan.lastOrderTime
      ? plan.lastOrderTime
      : plan.autoCloseTime,
  )
  if (openM == null || closeM == null) {
    // No schedule → fall back to openYn only (caller handles)
    return plan.open
  }
  const cur = minutesNow(now)
  if (closeM > openM) {
    return cur >= openM && cur < closeM
  }
  // Overnight window (rare for cafe)
  return cur >= openM || cur < closeM
}

/**
 * Decide whether the cafe accepts orders at `now`.
 * Prefer live openYn + pause/break flags from the sales-plan API.
 */
export function evaluateCafeHours(
  plan: CafeSalesPlan | null | undefined,
  now: Date = new Date(),
): CafeHoursStatus {
  if (!plan) {
    return {
      orderable: false,
      reason: 'unknown',
      hoursLabel: '',
      statusLabel: '확인 중',
      message: '영업 정보를 확인하는 중입니다',
      plan: null,
    }
  }

  const hoursLabel = formatHoursRange(plan.autoOpenTime, plan.autoCloseTime)
  const hoursPart = hoursLabel ? `운영 ${hoursLabel}` : '운영시간 확인'

  if (plan.pauseOrder) {
    return {
      orderable: false,
      reason: 'pause',
      hoursLabel,
      statusLabel: '주문 중지',
      message: `주문이 일시 중지되었습니다. ${hoursPart}`,
      plan,
    }
  }

  if (plan.nowBreak) {
    return {
      orderable: false,
      reason: 'break',
      hoursLabel,
      statusLabel: '브레이크',
      message: `브레이크 타임입니다. ${hoursPart}`,
      plan,
    }
  }

  // Server says open
  if (plan.open) {
    if (
      plan.lastOrderUse &&
      plan.lastOrderTime &&
      !scheduleAllowsOrder(
        { ...plan, lastOrderUse: true },
        now,
      ) &&
      isOpenDay(plan, now)
    ) {
      // Past last-order cutoff while flag still open
      return {
        orderable: false,
        reason: 'last_order_ended',
        hoursLabel,
        statusLabel: '라스트오더 종료',
        message: `라스트 오더가 종료되었습니다. ${hoursPart}`,
        plan,
      }
    }
    return {
      orderable: true,
      reason: 'open',
      hoursLabel,
      statusLabel: hoursLabel ? `영업 중 · ${hoursLabel}` : '영업 중',
      message: hoursLabel
        ? `영업 중 · 오늘 ${hoursLabel}`
        : '영업 중입니다',
      plan,
    }
  }

  // Server closed — refine message with schedule
  if (plan.openDays.length && !isOpenDay(plan, now)) {
    return {
      orderable: false,
      reason: 'closed_day',
      hoursLabel,
      statusLabel: '휴무',
      message: hoursLabel
        ? `오늘은 휴무입니다. 운영일 ${hoursLabel}`
        : '오늘은 휴무입니다',
      plan,
    }
  }

  return {
    orderable: false,
    reason: 'closed',
    hoursLabel,
    statusLabel: hoursLabel ? `마감 · ${hoursLabel}` : '마감',
    message: hoursLabel
      ? `지금은 주문할 수 없습니다. 운영시간 ${hoursLabel}`
      : '지금은 주문할 수 없습니다',
    plan,
  }
}

/** True when cart add / checkout should be allowed. */
export function isCafeOrderable(
  plan: CafeSalesPlan | null | undefined,
  now: Date = new Date(),
): boolean {
  return evaluateCafeHours(plan, now).orderable
}
