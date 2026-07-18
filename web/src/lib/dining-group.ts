import type { DiningCourse, DiningMenuItem, DiningPeriod } from './types'
import { todayISODate } from './format'

/** One dish after collapsing duplicate menu names across courses. */
export interface GroupedDiningDish {
  /** Stable key — normalized menu name */
  key: string
  name: string
  imageUrl: string | null
  calorie: number | null
  nutrition: string
  /** Free-text detail from API (often 반찬/구성 설명) */
  information: string
  /**
   * Side dishes from the same course (other meal rows under a main dish).
   * Empty when each meal is an independent item (e.g. take-out list).
   */
  sideDishes: string[]
  soldOut: boolean
  /** Course labels that serve this dish, e.g. ["한식A", "팝업A"] */
  courseNames: string[]
  /** Worst congestion among source courses, if any */
  congestion: string | null
  /** First non-empty origin text among courses */
  origin: string
}

const CONGESTION_RANK: Record<string, number> = {
  SMOOTH: 1,
  NORMAL: 2,
  CROWDED: 3,
}

export function normalizeMenuName(name: string): string {
  return name.trim().replace(/\s+/g, ' ')
}

function worseCongestion(a: string | null, b: string | null): string | null {
  if (!a) return b
  if (!b) return a
  const ra = CONGESTION_RANK[a] ?? 0
  const rb = CONGESTION_RANK[b] ?? 0
  return rb > ra ? b : a
}

function mergeUnique(dst: string[], extra: string[]): string[] {
  const out = [...dst]
  for (const s of extra) {
    const n = normalizeMenuName(s)
    if (!n) continue
    if (!out.some((x) => normalizeMenuName(x) === n)) out.push(s.trim())
  }
  return out
}

/** Courses that list separate sellable items, not a main + 반찬 set. */
function isIndependentItemCourse(courseName: string): boolean {
  const n = courseName.trim()
  return /take\s*out|테이크\s*아웃|takeout|포장|grab\s*&?\s*go|more\s*bite|to\s*go|샐러드바|salad/i.test(
    n,
  )
}

/**
 * Within a course:
 * - TAKE OUT / multi-item lists → every meal is its own row
 * - Classic 한식 set → only when exactly one photo main and the rest are
 *   image-less sides, fold sides under the main
 */
function splitCourseMenus(
  courseName: string,
  menus: DiningMenuItem[],
): Array<{
  main: DiningMenuItem
  sides: string[]
}> {
  const valid = menus.filter((m) => normalizeMenuName(m.name || ''))
  if (!valid.length) return []

  const asIndependent = () =>
    valid.map((main) => ({ main, sides: [] as string[] }))

  if (isIndependentItemCourse(courseName) || valid.length === 1) {
    return asIndependent()
  }

  const withImgIdx = valid
    .map((m, i) => (m.imageUrl ? i : -1))
    .filter((i) => i >= 0)

  // Only fold 반찬 when there is exactly one photo dish and ≥1 image-less items
  if (withImgIdx.length === 1) {
    const mainIdx = withImgIdx[0]
    const others = valid.filter((_, i) => i !== mainIdx)
    const othersAreSideless = others.every((m) => !m.imageUrl)
    if (othersAreSideless && others.length > 0) {
      return [
        {
          main: valid[mainIdx],
          sides: others.map((m) => normalizeMenuName(m.name)),
        },
      ]
    }
  }

  return asIndependent()
}

/** True when dish has any expandable 반찬/구성 detail. */
export function dishHasSides(dish: GroupedDiningDish): boolean {
  return (
    dish.sideDishes.length > 0 ||
    Boolean(dish.information?.trim()) ||
    Boolean(dish.nutrition?.trim())
  )
}

/** Text body for 반찬/구성 (legacy name kept). */
export function formatDishSidesBody(dish: GroupedDiningDish): string {
  const parts: string[] = []
  if (dish.sideDishes.length) {
    parts.push(dish.sideDishes.join(', '))
  }
  if (dish.information?.trim()) {
    parts.push(dish.information.trim())
  }
  if (dish.nutrition?.trim()) {
    parts.push(dish.nutrition.trim())
  }
  return parts.join('\n')
}

/** Full preview detail: 반찬 + 원산지 + 영양. */
export function formatDishPreviewDetail(dish: GroupedDiningDish): string {
  const parts: string[] = []
  if (dish.sideDishes.length) {
    parts.push(`반찬: ${dish.sideDishes.join(', ')}`)
  }
  if (dish.information?.trim()) {
    parts.push(dish.information.trim())
  }
  if (dish.nutrition?.trim()) {
    parts.push(dish.nutrition.trim())
  }
  if (dish.origin?.trim()) {
    parts.push(`원산지: ${dish.origin.trim()}`)
  }
  return parts.join('\n')
}

export function dishPreviewFromGroup(
  dish: GroupedDiningDish,
  caption?: string,
): {
  src: string | null
  alt: string
  caption: string
  detail?: string
} {
  const detail = formatDishPreviewDetail(dish)
  return {
    src: dish.imageUrl, // ImagePreview / MenuThumb show “준비 중” when null
    alt: dish.name,
    caption: caption || dish.name,
    detail: detail || undefined,
  }
}

/**
 * Flatten period courses into unique dishes.
 * Same menu name across 한식A / 팝업A etc. becomes one row with merged course labels.
 * Photo mains absorb same-course 반찬 rows into `sideDishes`.
 */
export function groupDiningDishes(
  courses: DiningCourse[] | null | undefined,
): GroupedDiningDish[] {
  if (!courses?.length) return []
  const map = new Map<string, GroupedDiningDish>()
  const order: string[] = []

  for (const course of courses) {
    const courseName = (course.name || '').trim() || '코스'
    for (const { main: meal, sides } of splitCourseMenus(
      courseName,
      course.menus,
    )) {
      const name = normalizeMenuName(meal.name || '')
      if (!name) continue
      const key = name
      const existing = map.get(key)
      if (!existing) {
        map.set(key, {
          key,
          name,
          imageUrl: meal.imageUrl,
          calorie: meal.calorie,
          nutrition: meal.nutrition || '',
          information: meal.information || '',
          sideDishes: [...sides],
          soldOut: Boolean(meal.soldOut || course.soldOut),
          courseNames: [courseName],
          congestion: course.congestion,
          origin: course.origin || '',
        })
        order.push(key)
        continue
      }
      if (!existing.courseNames.includes(courseName)) {
        existing.courseNames.push(courseName)
      }
      existing.soldOut =
        existing.soldOut && Boolean(meal.soldOut || course.soldOut)
      if (!existing.imageUrl && meal.imageUrl) {
        existing.imageUrl = meal.imageUrl
      }
      if (existing.calorie == null && meal.calorie != null) {
        existing.calorie = meal.calorie
      }
      if (!existing.nutrition && meal.nutrition) {
        existing.nutrition = meal.nutrition
      }
      if (!existing.information && meal.information) {
        existing.information = meal.information
      }
      existing.sideDishes = mergeUnique(existing.sideDishes, sides)
      if (!existing.origin && course.origin) {
        existing.origin = course.origin
      }
      existing.congestion = worseCongestion(
        existing.congestion,
        course.congestion,
      )
    }
  }

  return order.map((k) => map.get(k)!)
}

export function groupPeriodDishes(
  period: DiningPeriod | null | undefined,
): GroupedDiningDish[] {
  return groupDiningDishes(period?.courses)
}

/** Normalize "11:00" / "11:00:00" → seconds since midnight for compare. */
export function timeToSeconds(t: string | null | undefined): number | null {
  if (!t) return null
  const m = String(t).trim().match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?/)
  if (!m) return null
  const h = Number(m[1])
  const min = Number(m[2])
  const s = Number(m[3] ?? 0)
  if (![h, min, s].every((n) => Number.isFinite(n))) return null
  return h * 3600 + min * 60 + s
}

function nowSeconds(now = new Date()): number {
  return now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()
}

/**
 * Pick the meal period tab that best matches `now` (default: wall clock).
 *
 * - Currently open window → that period
 * - Before first meal → first period
 * - Between meals → next upcoming period
 * - After last meal ends → last period
 * - Viewing a non-today date → prefer 중식/lunch label, else first
 */
export function pickBestPeriodIndex(
  periods: DiningPeriod[],
  opts?: { now?: Date; dateISO?: string },
): number {
  if (!periods.length) return 0
  const now = opts?.now ?? new Date()
  const dateISO = opts?.dateISO
  const isToday = !dateISO || dateISO === todayISODate(now)

  if (!isToday) {
    const lunch = periods.findIndex((p) => /중식|lunch/i.test(p.time || ''))
    return lunch >= 0 ? lunch : 0
  }

  const t = nowSeconds(now)
  const bounds = periods.map((p, i) => ({
    i,
    start: timeToSeconds(p.startTime) ?? 0,
    end: timeToSeconds(p.endTime) ?? 24 * 3600 - 1,
  }))

  // 1) Currently in a service window (inclusive)
  const live = bounds.find((b) => t >= b.start && t <= b.end)
  if (live) return live.i

  // 2) Next upcoming period (closest future start)
  const upcoming = bounds
    .filter((b) => b.start > t)
    .sort((a, b) => a.start - b.start)
  if (upcoming.length) return upcoming[0].i

  // 3) All periods ended → last by end time
  const last = [...bounds].sort((a, b) => b.end - a.end)[0]
  return last?.i ?? periods.length - 1
}

export function pickBestPeriod(
  periods: DiningPeriod[],
  opts?: { now?: Date; dateISO?: string },
): DiningPeriod | null {
  if (!periods.length) return null
  return periods[pickBestPeriodIndex(periods, opts)] ?? null
}

/** Canonical slug for deep links / notifications: breakfast | lunch | dinner | raw */
export function periodSlug(period: Pick<DiningPeriod, 'time'> | null | undefined): string {
  const t = period?.time || ''
  if (/조식|breakfast/i.test(t)) return 'breakfast'
  if (/중식|lunch/i.test(t)) return 'lunch'
  if (/석식|dinner|저녁/i.test(t)) return 'dinner'
  const raw = t.trim().toLowerCase().replace(/\s+/g, '-')
  return raw || 'meal'
}

/** Match query `period` / `meal` against a dining period. */
export function periodMatchesQuery(
  period: Pick<DiningPeriod, 'time'>,
  query: string | null | undefined,
): boolean {
  if (!query) return false
  const q = query.trim().toLowerCase()
  if (!q) return false
  const slug = periodSlug(period)
  if (slug === q) return true
  if ((period.time || '').trim().toLowerCase() === q) return true
  // Korean aliases
  if (q === '조식' && slug === 'breakfast') return true
  if (q === '중식' && slug === 'lunch') return true
  if (q === '석식' || q === '저녁') return slug === 'dinner'
  return false
}

/** Whether wall-clock `now` is inside the period service window. */
export function isPeriodLive(
  period: Pick<DiningPeriod, 'startTime' | 'endTime'>,
  now = new Date(),
): boolean {
  const t = nowSeconds(now)
  const start = timeToSeconds(period.startTime) ?? 0
  const end = timeToSeconds(period.endTime) ?? 24 * 3600 - 1
  return t >= start && t <= end
}
