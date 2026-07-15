/**
 * Map raw Eliga API envelopes to skill-shaped view models (fmt.py parity).
 */
import { calcPlanPrice, localizeName } from './format'
import type {
  CafeCategory,
  CafeMenuItem,
  Cart,
  CartItem,
  DiningPeriod,
  GoodsOption,
  GoodsVariant,
  MenuDetail,
  PaymentReason,
  Shop,
} from './types'

function asArray<T>(v: unknown): T[] {
  return Array.isArray(v) ? (v as T[]) : []
}

function contentOf(data: unknown): unknown {
  if (data && typeof data === 'object' && 'content' in data) {
    return (data as { content: unknown }).content
  }
  return data
}

export function mapShops(raw: unknown): Shop[] {
  const content = asArray<Record<string, unknown>>(contentOf(raw))
  return content.map((shop) => ({
    shopId: Number(shop.id),
    name: localizeName(shop.name),
    type: String(shop.type ?? ''),
    open: Boolean(shop.openYn),
  }))
}

export function mapCafeCategories(raw: unknown): CafeCategory[] {
  const content = asArray<Record<string, unknown>>(contentOf(raw))
  return content.map((cat) => ({
    id: Number(cat.id),
    name: localizeName(cat.name),
    mobileUseYn: cat.mobileUseYn !== false,
    goodsCount: Number(cat.goodsDisplayCount ?? 0),
  }))
}

export function mapCafeMenu(raw: unknown, hiddenCatIds: Set<number> = new Set()): CafeMenuItem[] {
  const content = asArray<Record<string, unknown>>(contentOf(raw))
  const result: CafeMenuItem[] = []
  for (const item of content) {
    const catId = Number(item.categoryId)
    if (hiddenCatIds.size && hiddenCatIds.has(catId)) continue
    const rep = (item.repGoods as Record<string, unknown>) || {}
    result.push({
      displayId: Number(item.id),
      goodsId: rep.id != null ? Number(rep.id) : null,
      name: localizeName(item.name),
      category: localizeName(item.categoryName),
      price: calcPlanPrice(rep.goodsPricePlans as never),
      soldOut: Boolean(rep.soldOutYn),
      description: localizeName(rep.description) || null,
      calorie: (rep.calorie as number) ?? null,
      nutrition: localizeName(rep.nutrition) || null,
      label: normalizeLabel(item.labelOptionType),
      displayName: localizeName(rep.displayName),
    })
  }
  return result
}

function parseGoods(goods: Record<string, unknown>): GoodsVariant {
  const options: GoodsOption[] = []
  for (const opt of asArray<Record<string, unknown>>(goods.goodsOptions)) {
    if (!opt.activationType) continue
    const menus = asArray<Record<string, unknown>>(opt.goodsOptionMenus).map((menu) => ({
      menuId: Number(menu.id),
      name: localizeName(menu.name),
      price: calcPlanPrice(menu.goodsOptionMenuPrices as never, 'optionPrice'),
    }))
    options.push({
      optionId: Number(opt.id),
      name: localizeName(opt.name),
      multiSelect: Boolean(opt.multiSelectYn),
      menus,
    })
  }
  return {
    goodsId: Number(goods.id),
    name: localizeName(goods.name),
    displayName: localizeName(goods.displayName),
    price: calcPlanPrice(goods.goodsPricePlans as never),
    soldOut: Boolean(goods.soldOutYn),
    description: localizeName(goods.description) || null,
    calorie: (goods.calorie as number) ?? null,
    nutrition: localizeName(goods.nutrition) || null,
    options,
  }
}

export function mapCafeMenuDetail(raw: unknown): MenuDetail {
  let content = contentOf(raw) as Record<string, unknown>
  if (Array.isArray(content)) {
    content = (content[0] as Record<string, unknown>) || {}
  }
  let goodsList = content.goods
  if (!Array.isArray(goodsList)) {
    goodsList = goodsList ? [goodsList] : []
  }
  const goodsArr = asArray<Record<string, unknown>>(goodsList)
  return {
    displayId: Number(content.id),
    shopId: goodsArr[0]?.shopId != null ? Number(goodsArr[0].shopId) : null,
    label: normalizeLabel(content.labelOptionType),
    variants: goodsArr.map(parseGoods),
  }
}

/** BEST/NEW only — hide NONE/null labels in UI */
function normalizeLabel(v: unknown): string | null {
  if (v == null) return null
  const s = String(v).trim()
  if (!s || s.toUpperCase() === 'NONE') return null
  return s
}

export function mapDiningMenu(raw: unknown): DiningPeriod[] {
  const content = asArray<Record<string, unknown>>(contentOf(raw))
  const result: DiningPeriod[] = []
  for (const day of content) {
    for (const ot of asArray<Record<string, unknown>>(day.mealOperationTimes)) {
      const courses = asArray<Record<string, unknown>>(ot.courses).map((course) => {
        const menus = asArray<Record<string, unknown>>(course.meals).map((m) => ({
          name: localizeName(m.name),
          calorie: (m.calorie as number) ?? null,
          nutrition: localizeName(m.nutrition),
          information: localizeName(m.information),
        }))
        return {
          name: localizeName(course.name),
          price: calcPlanPrice(course.pricePlans as never),
          menus,
          soldOut: Boolean(course.soldOutYn),
          congestion: (course.congestionType as string) ?? null,
          origin: localizeName(course.origin),
        }
      })
      result.push({
        time: localizeName(ot.title),
        startTime: String(ot.startTime ?? ''),
        endTime: String(ot.endTime ?? ''),
        courses,
      })
    }
  }
  return result
}

export function mapCart(raw: unknown): Cart {
  const content = contentOf(raw) as Record<string, unknown> | null
  const cart = content && (content.cart as Record<string, unknown> | null)
  if (!cart) return { cartId: null, items: [] }

  const items: CartItem[] = asArray<Record<string, unknown>>(cart.goodsCartItems).map(
    (item) => {
      const detail = (item.goodsDetail as Record<string, unknown>) || {}
      const opts: CartItem['options'] = []
      for (const opt of asArray<Record<string, unknown>>(item.goodsCartItemOptions)) {
        const optInfo = (opt.goodsOption as Record<string, unknown>) || {}
        for (const menu of asArray<Record<string, unknown>>(opt.goodsCartItemOptionMenus)) {
          const menuInfo = (menu.goodsOptionMenu as Record<string, unknown>) || {}
          opts.push({
            option: localizeName(optInfo.name),
            value: localizeName(menuInfo.name),
          })
        }
      }
      return {
        cartItemId: Number(item.id),
        goodsId: Number(detail.id),
        name: localizeName(detail.name),
        qty: Number(item.goodsQty ?? 0),
        price: calcPlanPrice(detail.goodsPricePlans as never),
        options: opts,
      }
    },
  )

  return {
    cartId: cart.id != null ? Number(cart.id) : null,
    shopId: cart.shopId != null ? Number(cart.shopId) : undefined,
    items,
  }
}

export function mapPaymentReasons(raw: unknown): PaymentReason[] {
  const content = asArray<Record<string, unknown>>(contentOf(raw))
  return content
    .filter((r) => r.useYn !== false)
    .map((r) => ({
      id: Number(r.id),
      reason: localizeName(r.reason),
    }))
}

export function hiddenCategoryIds(categories: CafeCategory[]): Set<number> {
  return new Set(categories.filter((c) => !c.mobileUseYn).map((c) => c.id))
}
