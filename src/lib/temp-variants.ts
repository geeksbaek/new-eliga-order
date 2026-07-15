/**
 * HOT / ICE temperature variants for cafe menu detail.
 * List rows share a displayId; temperature is usually a separate goods variant.
 */
import type { GoodsVariant } from './types'

export type TempKind = 'hot' | 'ice' | 'other'

export function classifyTemp(variant: Pick<GoodsVariant, 'name' | 'displayName'>): TempKind {
  const s = `${variant.displayName ?? ''} ${variant.name ?? ''}`
  // ICED before ICE so "ICED" is not mis-read; HOT/ICE as whole tokens or hangul
  if (/\bHOT\b|핫|뜨거/i.test(s)) return 'hot'
  if (/\bICED?\b|아이스|차갑|콜드/i.test(s)) return 'ice'
  return 'other'
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

/** First available variant, preferring goodsId match from list row when present. */
export function pickDefaultVariant(
  variants: GoodsVariant[],
  preferredGoodsId?: number | null,
): GoodsVariant | null {
  if (!variants.length) return null
  if (preferredGoodsId != null) {
    const hit =
      variants.find((v) => v.goodsId === preferredGoodsId && !v.soldOut) ??
      variants.find((v) => v.goodsId === preferredGoodsId)
    if (hit && !hit.soldOut) return hit
  }
  return variants.find((v) => !v.soldOut) ?? null
}

/** Strip trailing HOT/ICE from display title. */
export function baseMenuTitle(name: string): string {
  return name.replace(/\s*(HOT|ICED|ICE)\s*$/i, '').trim() || name
}
