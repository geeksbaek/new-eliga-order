import type { GoodsOption, GoodsVariant, SelectedOption } from './types'

/** multiSelect groups that should behave as exclusive (e.g. 연하게 vs 샷추가) */
export function isExclusiveMultiGroup(opt: GoodsOption): boolean {
  if (!opt.multiSelect) return false
  if (opt.menus.length <= 1) return false
  if (opt.menus.every((m) => m.name.trim().startsWith('※'))) return false
  return true
}

function isNoticeMenu(name: string): boolean {
  return name.trim().startsWith('※')
}

function isNoneMenu(name: string): boolean {
  return /없음|안\s*함|선택\s*안\s*함|기본|보통/.test(name.replace(/\s/g, ''))
}

/**
 * Default option picks for a variant.
 * - Single-select: first menu (required default)
 * - Multi notice-only (※…): all selected
 * - Exclusive multi (샷추가 등): none selected (기본 = 추가 없음)
 * - Other multi: prefer a "없음" style menu if present, else none
 */
export function defaultSelections(
  variant: GoodsVariant,
): Record<number, number[]> {
  const out: Record<number, number[]> = {}
  for (const opt of variant.options) {
    if (!opt.menus.length) {
      out[opt.optionId] = []
      continue
    }

    if (!opt.multiSelect) {
      out[opt.optionId] = [opt.menus[0].menuId]
      continue
    }

    // multi
    if (opt.menus.every((m) => isNoticeMenu(m.name))) {
      out[opt.optionId] = opt.menus.map((m) => m.menuId)
      continue
    }

    if (isExclusiveMultiGroup(opt)) {
      // 기본: 연하게/샷추가 모두 선택 안 함
      out[opt.optionId] = []
      continue
    }

    const none = opt.menus.find((m) => isNoneMenu(m.name))
    out[opt.optionId] = none ? [none.menuId] : []
  }
  return out
}

/** Only options that have at least one menu pick (UI state → payload). */
export function selectionsToOptions(
  variant: GoodsVariant,
  selected: Record<number, number[]>,
): SelectedOption[] {
  return variant.options.flatMap((opt) => {
    const menuIds = (selected[opt.optionId] ?? []).filter((mid) =>
      opt.menus.some((m) => m.menuId === mid),
    )
    if (!menuIds.length) return []
    return [{ optionId: opt.optionId, menuIds }]
  })
}

/**
 * Full default cart options for list +/- quick add.
 * Includes every option group that has a default pick so 필수 옵션(컵 등)이
 * always travel with the cart line.
 */
export function defaultCartOptions(variant: GoodsVariant): SelectedOption[] {
  return selectionsToOptions(variant, defaultSelections(variant))
}

/** True if every single-select option has a default menu. */
export function hasCompleteSingleDefaults(variant: GoodsVariant): boolean {
  const sel = defaultSelections(variant)
  return variant.options.every((opt) => {
    if (opt.multiSelect) return true
    return (sel[opt.optionId] ?? []).length > 0
  })
}
