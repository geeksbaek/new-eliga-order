import type { CartItem, SelectedOption, GoodsOption } from './types'

export function lineTotal(item: Pick<CartItem, 'price' | 'qty'>): number {
  const price = Number(item.price) || 0
  const qty = Number(item.qty) || 0
  return price * qty
}

export function cartGrandTotal(
  items: Array<Pick<CartItem, 'price' | 'qty'>>,
): number {
  return items.reduce((sum, item) => sum + lineTotal(item), 0)
}

export function cartItemCount(
  items: Array<Pick<CartItem, 'qty'>>,
): number {
  return items.reduce((sum, item) => sum + (Number(item.qty) || 0), 0)
}

/** Option menu extra prices summed for one unit. */
export function optionExtrasTotal(
  options: GoodsOption[],
  selected: SelectedOption[],
): number {
  let total = 0
  for (const sel of selected) {
    const group = options.find((o) => o.optionId === sel.optionId)
    if (!group) continue
    const menuIds =
      sel.menuIds && sel.menuIds.length > 0
        ? sel.menuIds
        : sel.menuId != null
          ? [sel.menuId]
          : []
    for (const mid of menuIds) {
      const menu = group.menus.find((m) => m.menuId === mid)
      if (menu) total += Number(menu.price) || 0
    }
  }
  return total
}

export function unitPriceWithOptions(
  basePrice: number,
  options: GoodsOption[],
  selected: SelectedOption[],
): number {
  return (Number(basePrice) || 0) + optionExtrasTotal(options, selected)
}
