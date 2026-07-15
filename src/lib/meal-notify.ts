/**
 * Meal menu browser notifications (중식/석식 등).
 * Prefs live in localStorage; firing uses Notification API (+ optional SW).
 */
import { fetchDiningMenu } from '../api/eliga'
import { groupDiningDishes } from './dining-group'
import { todayISODate } from './format'
import { CAFETERIA_SHOP_ID } from './shop-rules'
import type { DiningPeriod } from './types'

export type MealSlot = 'breakfast' | 'lunch' | 'dinner'

export type MealNotifyPref = {
  enabled: boolean
  /** Local wall-clock "HH:mm" */
  time: string
}

export type NotificationPrefs = {
  meals: Record<MealSlot, MealNotifyPref>
  /** Cafeteria shop for menu fetch */
  shopId: number
  /** dayISO:slot → sent dayISO (idempotency) */
  lastSent: Partial<Record<string, string>>
}

export const MEAL_SLOTS: ReadonlyArray<{
  id: MealSlot
  label: string
  defaultTime: string
  pattern: RegExp
}> = [
  {
    id: 'breakfast',
    label: '조식',
    defaultTime: '07:30',
    pattern: /조식|breakfast/i,
  },
  {
    id: 'lunch',
    label: '중식',
    defaultTime: '10:40',
    pattern: /중식|lunch/i,
  },
  {
    id: 'dinner',
    label: '석식',
    defaultTime: '17:00',
    pattern: /석식|dinner|저녁/i,
  },
]

const PREFS_KEY = 'eliga.notify.prefs'
/** Fire window: pref time ≤ now ≤ pref + WINDOW_MIN minutes */
const WINDOW_MIN = 15

export function defaultNotificationPrefs(): NotificationPrefs {
  return {
    shopId: CAFETERIA_SHOP_ID,
    lastSent: {},
    meals: {
      breakfast: { enabled: false, time: '07:30' },
      lunch: { enabled: true, time: '10:40' },
      dinner: { enabled: true, time: '17:00' },
    },
  }
}

function isValidTime(t: string): boolean {
  return /^([01]?\d|2[0-3]):[0-5]\d$/.test(t.trim())
}

export function normalizeTime(t: string): string {
  const m = t.trim().match(/^(\d{1,2}):(\d{2})$/)
  if (!m) return '00:00'
  const h = Math.min(23, Math.max(0, Number(m[1])))
  const min = Math.min(59, Math.max(0, Number(m[2])))
  return `${String(h).padStart(2, '0')}:${String(min).padStart(2, '0')}`
}

export function loadNotificationPrefs(): NotificationPrefs {
  const base = defaultNotificationPrefs()
  try {
    const raw = localStorage.getItem(PREFS_KEY)
    if (!raw) return base
    const parsed = JSON.parse(raw) as Partial<NotificationPrefs>
    const meals = { ...base.meals }
    for (const slot of MEAL_SLOTS) {
      const src = parsed.meals?.[slot.id]
      if (!src) continue
      meals[slot.id] = {
        enabled: Boolean(src.enabled),
        time: isValidTime(src.time ?? '')
          ? normalizeTime(src.time!)
          : slot.defaultTime,
      }
    }
    return {
      shopId:
        typeof parsed.shopId === 'number' && Number.isFinite(parsed.shopId)
          ? parsed.shopId
          : base.shopId,
      lastSent:
        parsed.lastSent && typeof parsed.lastSent === 'object'
          ? parsed.lastSent
          : {},
      meals,
    }
  } catch {
    return base
  }
}

export function saveNotificationPrefs(prefs: NotificationPrefs): void {
  try {
    localStorage.setItem(PREFS_KEY, JSON.stringify(prefs))
  } catch {
    /* ignore quota */
  }
  try {
    window.dispatchEvent(new CustomEvent('eliga:notify-prefs'))
  } catch {
    /* ignore */
  }
}

export function anyMealNotifyEnabled(prefs: NotificationPrefs): boolean {
  return MEAL_SLOTS.some((s) => prefs.meals[s.id].enabled)
}

export function sentKey(dayISO: string, slot: MealSlot): string {
  return `${dayISO}:${slot}`
}

export function findPeriodForSlot(
  periods: DiningPeriod[],
  slot: MealSlot,
): DiningPeriod | null {
  const def = MEAL_SLOTS.find((s) => s.id === slot)
  if (!def) return null
  return periods.find((p) => def.pattern.test(p.time || '')) ?? null
}

export function formatMenuBody(period: DiningPeriod | null, label: string): {
  title: string
  body: string
} {
  if (!period) {
    return {
      title: `${label} 메뉴`,
      body: `오늘 ${label} 식단이 없습니다.`,
    }
  }
  const dishes = groupDiningDishes(period.courses)
  if (!dishes.length) {
    return {
      title: `${label} 메뉴`,
      body: `오늘 ${label} 식단이 없습니다.`,
    }
  }
  const lines = dishes.slice(0, 8).map((d) => {
    const course =
      d.courseNames.length === 1 ? d.courseNames[0] : d.courseNames.join('/')
    return course ? `${course} · ${d.name}` : d.name
  })
  const more = dishes.length > 8 ? `\n외 ${dishes.length - 8}개` : ''
  return {
    title: `${label} 메뉴 · 엘리가오더`,
    body: lines.join('\n') + more,
  }
}

export function minutesOfDay(time: string, now = new Date()): number {
  const norm = normalizeTime(time)
  const [h, m] = norm.split(':').map(Number)
  if (Number.isFinite(h) && Number.isFinite(m)) return h * 60 + m
  return now.getHours() * 60 + now.getMinutes()
}

export function shouldFireMeal(
  pref: MealNotifyPref,
  slot: MealSlot,
  prefs: NotificationPrefs,
  now = new Date(),
): boolean {
  if (!pref.enabled) return false
  const day = todayISODate(now)
  if (prefs.lastSent[sentKey(day, slot)] === day) return false
  const prefMin = minutesOfDay(pref.time, now)
  const nowMin = now.getHours() * 60 + now.getMinutes()
  if (nowMin < prefMin) return false
  if (nowMin > prefMin + WINDOW_MIN - 1) return false
  return true
}

export function notificationPermission(): NotificationPermission | 'unsupported' {
  if (typeof window === 'undefined' || !('Notification' in window)) {
    return 'unsupported'
  }
  return Notification.permission
}

export async function requestNotificationPermission(): Promise<
  NotificationPermission | 'unsupported'
> {
  if (typeof window === 'undefined' || !('Notification' in window)) {
    return 'unsupported'
  }
  if (Notification.permission === 'granted') return 'granted'
  if (Notification.permission === 'denied') return 'denied'
  try {
    return await Notification.requestPermission()
  } catch {
    return Notification.permission
  }
}

async function showViaSw(
  title: string,
  options: NotificationOptions,
): Promise<boolean> {
  if (!('serviceWorker' in navigator)) return false
  try {
    const reg = await navigator.serviceWorker.ready
    await reg.showNotification(title, options)
    return true
  } catch {
    return false
  }
}

export async function showMealNotification(
  title: string,
  body: string,
  url: string,
): Promise<boolean> {
  if (notificationPermission() !== 'granted') return false

  const options: NotificationOptions & {
    vibrate?: number[]
    renotify?: boolean
  } = {
    body,
    icon: '/favicon.svg',
    badge: '/favicon.svg',
    tag: `eliga-meal-${url}`,
    renotify: true,
    data: { url },
    vibrate: [80, 40, 80],
  }

  const viaSw = await showViaSw(title, options)
  if (viaSw) return true

  try {
    const n = new Notification(title, options)
    n.onclick = () => {
      try {
        window.focus()
        if (url) window.location.assign(url)
      } catch {
        /* ignore */
      }
      n.close()
    }
    return true
  } catch {
    return false
  }
}

export function markSent(
  prefs: NotificationPrefs,
  slot: MealSlot,
  day = todayISODate(),
): NotificationPrefs {
  const next: NotificationPrefs = {
    ...prefs,
    lastSent: { ...prefs.lastSent, [sentKey(day, slot)]: day },
  }
  saveNotificationPrefs(next)
  return next
}

/**
 * Fetch today's menu and show a notification for one meal slot.
 * `force` ignores the time window (for "미리보기" / test).
 */
export async function notifyMealSlot(
  slot: MealSlot,
  opts?: { force?: boolean; prefs?: NotificationPrefs },
): Promise<{ ok: boolean; reason?: string }> {
  let prefs = opts?.prefs ?? loadNotificationPrefs()
  const meta = MEAL_SLOTS.find((s) => s.id === slot)
  if (!meta) return { ok: false, reason: 'unknown-slot' }

  const pref = prefs.meals[slot]
  if (!opts?.force) {
    if (!shouldFireMeal(pref, slot, prefs)) {
      return { ok: false, reason: 'not-due' }
    }
  } else if (!pref.enabled && !opts.force) {
    return { ok: false, reason: 'disabled' }
  }

  if (notificationPermission() !== 'granted') {
    return { ok: false, reason: 'permission' }
  }

  const day = todayISODate()
  let periods: DiningPeriod[] = []
  try {
    periods = await fetchDiningMenu(prefs.shopId, day)
  } catch (e) {
    const msg = e instanceof Error ? e.message : '메뉴를 불러오지 못했습니다'
    await showMealNotification(
      `${meta.label} 알림`,
      msg,
      `/dining/${prefs.shopId}?period=${slot}`,
    )
    if (!opts?.force) prefs = markSent(prefs, slot, day)
    return { ok: false, reason: 'fetch' }
  }

  const period = findPeriodForSlot(periods, slot)
  const { title, body } = formatMenuBody(period, meta.label)
  const shown = await showMealNotification(
    title,
    body,
    `/dining/${prefs.shopId}?period=${slot}`,
  )
  if (!shown) return { ok: false, reason: 'show-failed' }
  if (!opts?.force) markSent(prefs, slot, day)
  return { ok: true }
}

/** Check all enabled slots and fire due notifications. */
export async function tickMealNotifications(): Promise<void> {
  const prefs = loadNotificationPrefs()
  if (!anyMealNotifyEnabled(prefs)) return
  if (notificationPermission() !== 'granted') return

  for (const slot of MEAL_SLOTS) {
    if (!shouldFireMeal(prefs.meals[slot.id], slot.id, prefs)) continue
    try {
      await notifyMealSlot(slot.id, { prefs })
      // reload after mark
    } catch {
      /* keep ticking other slots */
    }
  }
}

export const TIME_PRESETS = [
  '07:00',
  '07:30',
  '08:00',
  '10:30',
  '10:40',
  '11:00',
  '11:30',
  '16:30',
  '17:00',
  '17:30',
  '18:00',
] as const
