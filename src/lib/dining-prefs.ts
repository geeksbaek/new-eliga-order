/**
 * Dining food preferences (localStorage) + catalog of unique menu names
 * scraped from past cafeteria menus.
 */
import {
  normalizeMenuName,
  type GroupedDiningDish,
} from './dining-group'
import type { DiningPeriod } from './types'

const PREFS_KEY = 'eliga.dining.prefs'
/** v4: also parse 반찬 from meal.information [원산지] block */
const CATALOG_KEY = 'eliga.dining.catalog.v4'
/** Reuse history catalog for a week */
export const CATALOG_TTL_MS = 7 * 24 * 60 * 60 * 1000
/** How far back to scan for unique dishes */
export const CATALOG_LOOKBACK_DAYS = 90

export type DiningFoodCatalog = {
  shopId: number
  at: number
  names: string[]
}

/**
 * Normalize a 반찬/메뉴 label for catalog + preference matching.
 * - NFKC (전각 영문/숫자 정리)
 * - 괄호·대괄호 안 문구 제거: (HOT), [밸런스바이츠], …
 * - 영문 소문자 통일
 * - 공백·구분 기호 정리
 */
export function normalizeFoodName(name: string): string {
  let s = String(name ?? '')
  try {
    s = s.normalize('NFKC')
  } catch {
    /* ignore */
  }

  // Strip nested/simple bracket contents (half + full width)
  let prev = ''
  while (prev !== s) {
    prev = s
    s = s
      .replace(/\([^()]*\)/g, ' ')
      .replace(/\[[^[\]]*]/g, ' ')
      .replace(/\{[^{}]*\}/g, ' ')
      .replace(/（[^（）]*）/g, ' ')
      .replace(/【[^【】]*】/g, ' ')
      .replace(/「[^「」]*」/g, ' ')
      .replace(/『[^『』]*』/g, ' ')
      .replace(/〈[^〈〉]*〉/g, ' ')
      .replace(/《[^《》]*》/g, ' ')
  }
  s = s.replace(/[()[\]{}（）【】「」『』〈〉《》]/g, ' ')

  // Drop trailing " *extra " notes (e.g. 김밥*과일토핑)
  s = s.replace(/\*.*$/u, ' ')

  // Case-fold Latin; Korean unchanged
  s = s.toLowerCase()

  // Common separators → space
  s = s.replace(/[·•･・∙]/g, ' ')
  s = s.replace(/[_/|\\~]+/g, ' ')
  s = s.replace(/[–—-]+/g, ' ')

  // Trim leftover punctuation at ends
  s = s.replace(/^[\s.,;:!?'"`+]+|[\s.,;:!?'"`+]+$/g, '')

  // Collapse whitespace (reuse group helper spirit)
  s = s.replace(/\s+/g, ' ').trim()

  // If nothing left after stripping tags, fall back to lightly cleaned original
  if (!s) {
    let fb = normalizeMenuName(String(name ?? ''))
    try {
      fb = fb.normalize('NFKC')
    } catch {
      /* ignore */
    }
    s = fb.toLowerCase().replace(/\s+/g, ' ').trim()
  }

  return s
}

/** Drop noise rows that are not real dish names. */
export function isUsableFoodName(name: string): boolean {
  const n = normalizeFoodName(name)
  if (n.length < 2) return false
  if (/^side\s*\d/.test(n)) return false
  if (/^선택/.test(n)) return false
  if (n === 'none') return false
  if (/^(and|or|the|a|an)$/.test(n)) return false
  return true
}

export function loadDiningPrefs(): string[] {
  try {
    const raw = localStorage.getItem(PREFS_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw) as unknown
    if (!Array.isArray(parsed)) return []
    const out: string[] = []
    const seen = new Set<string>()
    for (const v of parsed) {
      if (typeof v !== 'string') continue
      const n = normalizeFoodName(v)
      if (!isUsableFoodName(n) || seen.has(n)) continue
      seen.add(n)
      out.push(n)
    }
    return out
  } catch {
    return []
  }
}

export function saveDiningPrefs(names: string[]): void {
  try {
    const clean = names
      .map(normalizeFoodName)
      .filter(isUsableFoodName)
    const seen = new Set<string>()
    const unique: string[] = []
    for (const n of clean) {
      if (seen.has(n)) continue
      seen.add(n)
      unique.push(n)
    }
    localStorage.setItem(PREFS_KEY, JSON.stringify(unique))
  } catch {
    /* quota */
  }
}

export function isDiningPref(
  name: string,
  list?: string[] | Set<string>,
): boolean {
  const n = normalizeFoodName(name)
  if (!n) return false
  if (list instanceof Set) return list.has(n)
  const prefs = list ?? loadDiningPrefs()
  return prefs.some((p) => p === n)
}

export function toggleDiningPref(name: string): string[] {
  const n = normalizeFoodName(name)
  if (!isUsableFoodName(n)) return loadDiningPrefs()
  const cur = loadDiningPrefs()
  const next = cur.includes(n) ? cur.filter((x) => x !== n) : [...cur, n]
  saveDiningPrefs(next)
  return next
}

export function prefsToSet(list?: string[]): Set<string> {
  return new Set((list ?? loadDiningPrefs()).map(normalizeFoodName))
}

/**
 * Lines under meal.information `[원산지]` are the actual 반찬 list.
 * Origin-only lines like `(소:호주산)` are skipped.
 *
 * Example block:
 *   [원산지]
 *   얼큰돈내장국밥
 *   병천순대찜*들깨초장
 *   (돼지:국내산)
 *   부추무침
 *   쌀밥
 *   섞박지
 *   [알러지주의음식]
 */
export function parseOriginFoodLines(information: string | null | undefined): string[] {
  const text = String(information ?? '').replace(/\r\n/g, '\n')
  if (!text.trim()) return []

  // Prefer [원산지] … until next [섹션]; else use full text when it looks line-based
  let body = ''
  const section = text.match(
    /\[원산지\]\s*([\s\S]*?)(?=\n\s*\[[^\]]+\]\s*(?:\n|$)|$)/i,
  )
  if (section) {
    body = section[1]
  } else if (/^\s*\[[^\]]+\]/m.test(text)) {
    // Has other sections but no 원산지 — nothing to harvest
    return []
  } else {
    body = text
  }

  const out: string[] = []
  for (const rawLine of body.split('\n')) {
    const line = rawLine.trim()
    if (!line) continue
    // Pure origin notes: (소:호주산), (배추,고춧가루:국내산)
    if (/^[(\uff08].*[)\uff09]$/.test(line)) continue
    if (/^(국내산|외국산|호주산|중국산|미국산|칠레산)/.test(line)) continue
    // Skip leftover section headers
    if (/^\[[^\]]+\]$/.test(line)) continue
    // Skip long legal notices
    if (line.length > 40 && /원산지|참고|게시/.test(line)) continue

    // "메인*양념" → both parts as separate 반찬 chips
    const parts = line
      .split('*')
      .map((p) => p.trim())
      .filter(Boolean)
    for (const part of parts.length ? parts : [line]) {
      out.push(part)
    }
  }
  return out
}

/** All food labels on a dish row (main + folded sides + 원산지 목록). */
export function foodsOnDish(
  dish: Pick<GroupedDiningDish, 'name' | 'sideDishes' | 'information'>,
): string[] {
  const raw: string[] = [dish.name, ...(dish.sideDishes ?? [])]
  raw.push(...parseOriginFoodLines(dish.information))
  const seen = new Set<string>()
  const out: string[] = []
  for (const r of raw) {
    const n = normalizeFoodName(r)
    if (!isUsableFoodName(n) || seen.has(n)) continue
    seen.add(n)
    out.push(n)
  }
  return out
}

/**
 * Collect unique individual 반찬/메뉴 names from periods.
 * Includes meal.name and every line under information [원산지].
 */
export function extractFoodNamesFromPeriods(
  periods: DiningPeriod[],
): string[] {
  const seen = new Set<string>()
  const add = (raw: string) => {
    const n = normalizeFoodName(raw)
    if (isUsableFoodName(n)) seen.add(n)
  }
  for (const p of periods) {
    for (const course of p.courses ?? []) {
      for (const meal of course.menus ?? []) {
        add(meal.name || '')
        for (const line of parseOriginFoodLines(meal.information)) {
          add(line)
        }
      }
    }
  }
  return [...seen].sort((a, b) => a.localeCompare(b, 'ko'))
}

/** True when main, folded sides, or 원산지 반찬 is in prefs. */
export function dishMatchesPrefs(
  dish: Pick<GroupedDiningDish, 'name' | 'sideDishes' | 'information'>,
  prefs: Set<string> | string[],
): boolean {
  const set = prefs instanceof Set ? prefs : prefsToSet(prefs)
  if (set.size === 0) return false
  for (const f of foodsOnDish(dish)) {
    if (set.has(f)) return true
  }
  return false
}

/** Preferred dishes first; stable among equals. */
export function sortDishesByPref(
  dishes: GroupedDiningDish[],
  prefs: Set<string> | string[],
): GroupedDiningDish[] {
  const set = prefs instanceof Set ? prefs : prefsToSet(prefs)
  if (set.size === 0) return dishes
  return [...dishes].sort((a, b) => {
    const ma = dishMatchesPrefs(a, set) ? 0 : 1
    const mb = dishMatchesPrefs(b, set) ? 0 : 1
    return ma - mb
  })
}

export function loadDiningCatalog(shopId: number): DiningFoodCatalog | null {
  try {
    const raw = localStorage.getItem(CATALOG_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as DiningFoodCatalog
    if (!parsed || parsed.shopId !== shopId) return null
    if (!Array.isArray(parsed.names)) return null
    return parsed
  } catch {
    return null
  }
}

export function saveDiningCatalog(cat: DiningFoodCatalog): void {
  try {
    localStorage.setItem(CATALOG_KEY, JSON.stringify(cat))
  } catch {
    /* quota */
  }
}

export function isCatalogFresh(
  cat: DiningFoodCatalog | null | undefined,
  maxAgeMs = CATALOG_TTL_MS,
): boolean {
  if (!cat) return false
  return Date.now() - cat.at <= maxAgeMs
}
