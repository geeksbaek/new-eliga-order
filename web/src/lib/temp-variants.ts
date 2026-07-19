/**
 * HOT / ICE temperature variants for cafe menu detail.
 * List rows share a displayId; temperature is usually a separate goods variant.
 * Last user choice is stored in localStorage for default selection next time.
 */
import type { GoodsVariant } from './types'

export type TempKind = 'hot' | 'ice' | 'other'

/** Only ICE/HOT are remembered as prefs */
export type TempPref = 'hot' | 'ice'

const LAST_TEMP_KEY = 'eliga.cafe.lastTemp'

export function classifyTemp(variant: Pick<GoodsVariant, 'name' | 'displayName'>): TempKind {
  const s = `${variant.displayName ?? ''} ${variant.name ?? ''}`
  // ICED before ICE so "ICED" is not mis-read; HOT/ICE as whole tokens or hangul
  if (/\bHOT\b|핫|뜨거/i.test(s)) return 'hot'
  if (/\bICED?\b|아이스|차갑|콜드/i.test(s)) return 'ice'
  return 'other'
}

export function loadLastTempPref(): TempPref | null {
  try {
    const v = localStorage.getItem(LAST_TEMP_KEY)
    if (v === 'hot' || v === 'ice') return v
  } catch {
    /* ignore */
  }
  return null
}

export function saveLastTempPref(pref: TempPref): void {
  try {
    localStorage.setItem(LAST_TEMP_KEY, pref)
  } catch {
    /* ignore */
  }
}

/** Remember ICE/HOT when the user picks a temperature variant. */
export function rememberTempFromVariant(
  variant: Pick<GoodsVariant, 'name' | 'displayName'>,
): void {
  const kind = classifyTemp(variant)
  if (kind === 'hot' || kind === 'ice') saveLastTempPref(kind)
}

export type TempPickOption = {
  kind: 'hot' | 'ice'
  label: string
  variant: GoodsVariant
}

/**
 * When both HOT and ICE (non-sold-out) exist, the user must pick one.
 * Returns empty when no dialog is needed.
 */
export function tempPickOptions(variants: GoodsVariant[]): TempPickOption[] {
  const available = variants.filter((v) => !v.soldOut)
  let hot: GoodsVariant | null = null
  let ice: GoodsVariant | null = null
  for (const v of available) {
    const kind = classifyTemp(v)
    if (kind === 'hot' && !hot) hot = v
    if (kind === 'ice' && !ice) ice = v
  }
  if (!hot || !ice) return []

  return [
    {
      kind: 'ice',
      label: ice.displayName?.trim() || 'ICE',
      variant: ice,
    },
    {
      kind: 'hot',
      label: hot.displayName?.trim() || 'HOT',
      variant: hot,
    },
  ]
}

export function needsTempPick(variants: GoodsVariant[]): boolean {
  return tempPickOptions(variants).length >= 2
}

/**
 * Pick initial variant:
 * 1) last remembered ICE/HOT (if that temp is available)
 * 2) preferredGoodsId from list row
 * 3) first non-sold-out
 */
export function pickDefaultVariant(
  variants: GoodsVariant[],
  preferredGoodsId?: number | null,
  preferredTemp: TempPref | null = loadLastTempPref(),
): GoodsVariant | null {
  if (!variants.length) return null
  const available = variants.filter((v) => !v.soldOut)
  const pool = available.length ? available : variants

  if (preferredTemp === 'hot' || preferredTemp === 'ice') {
    const byTemp = pool.find((v) => classifyTemp(v) === preferredTemp)
    if (byTemp) return byTemp
  }

  if (preferredGoodsId != null) {
    const hit =
      pool.find((v) => v.goodsId === preferredGoodsId) ??
      variants.find((v) => v.goodsId === preferredGoodsId && !v.soldOut)
    if (hit && !hit.soldOut) return hit
  }

  return pool[0] ?? null
}

/** Strip trailing HOT/ICE from display title. */
export function baseMenuTitle(name: string): string {
  return name.replace(/\s*(HOT|ICED|ICE)\s*$/i, '').trim() || name
}
