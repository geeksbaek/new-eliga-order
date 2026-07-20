/**
 * Map raw Eliga API envelopes to skill-shaped view models (fmt.py parity).
 */
import {
  calcPlanPrice,
  localizeName,
  mediaUrl,
  parseKcalFromNutrition,
} from './format'
import type {
  CafeCategory,
  CafeMenuItem,
  CafeQuickItem,
  Cart,
  CartItem,
  DiningPeriod,
  GoodsOption,
  GoodsVariant,
  MenuDetail,
  OrderHistoryView,
  OrderLineView,
  PaymentReason,
  SelectedOption,
  Shop,
} from './types'
import type { StashedCartLine } from './quick-order'

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
    // API property only — mobile app hides mobileUseYn=false categories
    mobileUseYn: ynTrue(cat.mobileUseYn) || cat.mobileUseYn === true,
    goodsCount: Number(cat.goodsDisplayCount ?? 0),
  }))
}

/** Pull CDN image from display row / goods object (list + detail). */
function cafeImageFrom(...bags: Array<Record<string, unknown> | null | undefined>): string | null {
  const candidates: unknown[] = []
  for (const bag of bags) {
    if (!bag) continue
    candidates.push(
      bag.thumbnailPath,
      bag.thumbnail,
      bag.imagePath,
      bag.imageUrl,
      bag.filePath,
      bag.sharePath,
    )
  }
  for (const c of candidates) {
    if (typeof c === 'string' && c.trim()) {
      const url = mediaUrl(c)
      if (url) return url
    }
  }
  for (const bag of bags) {
    if (!bag) continue
    const files = asArray<Record<string, unknown>>(bag.fileItems)
    if (!files.length) continue
    const preferred =
      files.find((f) => f.thumbnailYn && f.filePath) ||
      files.find((f) => f.filePath) ||
      files.find((f) => f.sharePath) ||
      files[0]
    const url = mediaUrl(
      (preferred?.filePath as string) ||
        (preferred?.sharePath as string) ||
        null,
    )
    if (url) return url
  }
  return null
}

function cafeDisplayThumbnail(
  item: Record<string, unknown>,
  rep: Record<string, unknown>,
): string | null {
  return cafeImageFrom(item, rep)
}

function ynTrue(v: unknown): boolean {
  return v === true || v === 'Y' || v === 'y' || v === 1 || v === '1' || v === 'true'
}

function ynFalse(v: unknown): boolean {
  return v === false || v === 'N' || v === 'n' || v === 0 || v === '0' || v === 'false'
}

function readCategoryId(item: Record<string, unknown>): number | null {
  const nested =
    item.category && typeof item.category === 'object'
      ? (item.category as Record<string, unknown>).id
      : undefined
  for (const v of [
    item.categoryId,
    item.goodsCategoryId,
    item.goodsDisplayCategoryId,
    nested,
  ]) {
    if (v == null || v === '') continue
    const n = Number(v)
    if (Number.isFinite(n) && n > 0) return n
  }
  return null
}

function categoryLabelOf(item: Record<string, unknown>): string {
  const parts = [localizeName(item.categoryName)]
  if (item.category && typeof item.category === 'object') {
    parts.push(
      localizeName((item.category as Record<string, unknown>).name),
    )
  }
  return parts.filter(Boolean).join(' ')
}

/**
 * True when every goodsPricePlans entry is 0원 (ops test stubs like
 * "Test상품(지우지 말아주세요)"). Real menus have positive NORMAL/IDCARD prices.
 *
 * Recent/popular rows have no price plans — missing price is NOT zero.
 */
export function isZeroPriceCafeGoods(
  item: Record<string, unknown>,
  rep: Record<string, unknown> = {},
): boolean {
  const plans = asArray<Record<string, unknown>>(
    rep.goodsPricePlans ?? item.goodsPricePlans,
  )
  if (plans.length > 0) {
    return plans.every((p) => Number(p.price ?? 0) <= 0)
  }
  // Only treat as zero when an explicit price field is present
  const explicit =
    item.salePrice ?? item.price ?? rep.price ?? rep.salePrice
  if (explicit == null || explicit === '') return false
  const n = Number(explicit)
  return Number.isFinite(n) && n <= 0
}

/**
 * Hide non-sellable / test cafe displays.
 * - Explicit API flags (testYn, displayYn, …)
 * - 0원 goodsPricePlans (test stubs in real categories)
 * Category visibility is separate: mobileUseYn → hiddenCategoryIds.
 */
export function isTestCafeDisplay(
  item: Record<string, unknown>,
  rep: Record<string, unknown> = {},
): boolean {
  const testKeys = [
    'testYn',
    'isTest',
    'goodsTestYn',
    'testGoodsYn',
    'sampleYn',
    'demoYn',
    'dummyYn',
    'qaYn',
    'isTestGoods',
    'testDisplayYn',
  ] as const
  for (const bag of [item, rep]) {
    for (const k of testKeys) {
      if (k in bag && ynTrue(bag[k])) return true
    }
    if ('displayYn' in bag && ynFalse(bag.displayYn)) return true
    if ('mobileDisplayYn' in bag && ynFalse(bag.mobileDisplayYn)) return true
    if ('mobileYn' in bag && ynFalse(bag.mobileYn)) return true
    if ('useYn' in bag && ynFalse(bag.useYn)) return true
  }
  if (isZeroPriceCafeGoods(item, rep)) return true
  return false
}

export function mapCafeMenu(raw: unknown, hiddenCatIds: Set<number> = new Set()): CafeMenuItem[] {
  const content = asArray<Record<string, unknown>>(contentOf(raw))
  const result: CafeMenuItem[] = []
  for (const item of content) {
    const categoryId = readCategoryId(item)
    if (
      categoryId != null &&
      hiddenCatIds.size > 0 &&
      hiddenCatIds.has(categoryId)
    ) {
      continue
    }
    const rep = (item.repGoods as Record<string, unknown>) || {}
    if (isTestCafeDisplay(item, rep)) continue
    result.push({
      displayId: Number(item.id ?? item.displayId),
      goodsId: rep.id != null ? Number(rep.id) : null,
      name: localizeName(item.name),
      categoryId,
      category: categoryLabelOf(item) || localizeName(item.categoryName),
      price: calcPlanPrice(rep.goodsPricePlans as never) || Number(item.salePrice ?? item.price ?? 0),
      soldOut: Boolean(rep.soldOutYn ?? item.soldOutYn ?? item.soldoutYn),
      description: localizeName(rep.description) || null,
      calorie: (rep.calorie as number) ?? null,
      nutrition: localizeName(rep.nutrition) || null,
      label: normalizeLabel(item.labelOptionType),
      displayName: localizeName(rep.displayName),
      thumbnailUrl: cafeDisplayThumbnail(item, rep),
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
    thumbnailUrl: cafeImageFrom(goods),
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
  const variants = goodsArr.map(parseGoods)
  const displayThumb =
    cafeImageFrom(content) ||
    variants.find((v) => v.thumbnailUrl)?.thumbnailUrl ||
    null
  // Fill variants missing image with display-level hero
  const variantsWithImg = variants.map((v) =>
    v.thumbnailUrl
      ? v
      : { ...v, thumbnailUrl: displayThumb },
  )
  return {
    displayId: Number(content.id),
    shopId: goodsArr[0]?.shopId != null ? Number(goodsArr[0].shopId) : null,
    label: normalizeLabel(content.labelOptionType),
    thumbnailUrl: displayThumb,
    variants: variantsWithImg,
  }
}

/** BEST/NEW only — hide NONE/null labels in UI */
function normalizeLabel(v: unknown): string | null {
  if (v == null) return null
  const s = String(v).trim()
  if (!s || s.toUpperCase() === 'NONE') return null
  return s
}

function firstMealImage(meal: Record<string, unknown>): string | null {
  const files = asArray<Record<string, unknown>>(meal.fileItems)
  if (!files.length) return null
  // Prefer non-empty filePath; thumbnail if any
  const preferred =
    files.find((f) => f.thumbnailYn && f.filePath) ||
    files.find((f) => f.filePath) ||
    files[0]
  return mediaUrl(
    (preferred.filePath as string) ||
      (preferred.sharePath as string) ||
      null,
  )
}

export function mapDiningMenu(raw: unknown): DiningPeriod[] {
  const content = asArray<Record<string, unknown>>(contentOf(raw))
  const result: DiningPeriod[] = []
  for (const day of content) {
    for (const ot of asArray<Record<string, unknown>>(day.mealOperationTimes)) {
      const courses = asArray<Record<string, unknown>>(ot.courses).map((course) => {
        const menus = asArray<Record<string, unknown>>(course.meals).map((m) => {
          const nutrition = localizeName(m.nutrition)
          const calorie =
            (m.calorie as number) ?? parseKcalFromNutrition(nutrition)
          return {
            name: localizeName(m.name),
            calorie,
            nutrition,
            information: localizeName(m.information),
            imageUrl: firstMealImage(m),
            soldOut: Boolean(m.soldOutYn || m.stockEmptyYn),
          }
        })
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

function mapGoodsOrderLine(item: Record<string, unknown>): OrderLineView {
  const opts: string[] = []
  for (const opt of asArray<Record<string, unknown>>(item.goodsOrderItemOptions)) {
    const optName = localizeName(opt.optionName).trim()
    const menus = asArray<Record<string, unknown>>(opt.optionMenus)
    if (!menus.length) {
      // Option group present but no menu picks — skip (avoids empty "()")
      continue
    }
    for (const menu of menus) {
      const menuName = localizeName(menu.name).trim()
      // Empty menu pick → no label (prevents "()" or bare option names)
      if (!menuName) continue
      opts.push(optName ? `${optName}: ${menuName}` : menuName)
    }
  }
  const qty = Number(item.goodsQty ?? item.qty ?? 1) || 1
  const price = Number(
    item.paidPrice ?? item.salesPrice ?? item.unitPrice ?? 0,
  )
  return {
    name: localizeName(item.name ?? item.displayName ?? item.goodsName),
    qty,
    price,
    options: opts,
  }
}

/** Cafeteria meal lines use mealName / mealQty / courseName */
function mapMealOrderLine(item: Record<string, unknown>): OrderLineView {
  const course = localizeName(item.courseName)
  const op = localizeName(item.operationTimeTitle)
  const meal = localizeName(item.mealName)
  const label = [op, course, meal].filter(Boolean).join(' · ')
  const qty = Number(item.mealQty ?? item.goodsQty ?? 1) || 1
  const price = Number(
    item.paidPrice ?? item.salesPrice ?? item.unitPrice ?? 0,
  )
  return {
    name: label || meal || '식단',
    qty,
    price,
    options: [],
  }
}

export function mapOrderHistory(raw: unknown): OrderHistoryView[] {
  const list = asArray<Record<string, unknown>>(contentOf(raw))
  return list.map((row) => {
    const goodsItems = asArray<Record<string, unknown>>(row.goodsOrderItems).map(
      mapGoodsOrderLine,
    )
    const mealItems = asArray<Record<string, unknown>>(row.mealOrderItems).map(
      mapMealOrderLine,
    )
    const items = [...goodsItems, ...mealItems]
    const totalPaid = Number(
      row.totalPaidPrice ??
        row.totalSalesPrice ??
        row.totalUnitPrice ??
        items.reduce((s, it) => s + it.price, 0),
    )
    return {
      orderId: Number(row.orderId ?? row.id ?? 0),
      orderNo: String(row.orderNo ?? row.orderId ?? ''),
      shopId: Number(row.shopId ?? 0),
      shopName: localizeName(row.shopName),
      shopType: String(row.shopType ?? ''),
      status: String(row.status ?? row.orderStatus ?? ''),
      orderedAt: String(row.regAt ?? row.createdAt ?? row.orderDate ?? ''),
      totalPaid,
      items,
    }
  })
}

export function mapCafeQuickItems(raw: unknown): CafeQuickItem[] {
  const list = asArray<Record<string, unknown>>(contentOf(raw))
  return list
    .filter((row) => !isTestCafeDisplay(row, row))
    .map((row) => ({
      displayId: Number(row.displayId ?? 0),
      goodsId: Number(row.goodsId ?? 0),
      name: localizeName(row.name),
      qty: Number(row.goodsQty ?? 1) || 1,
      thumbnailUrl:
        row.thumbnailYn === false
          ? null
          : mediaUrl(row.thumbnail as string),
      soldOut: Boolean(row.stockEmptyYn) || row.isSale === false,
      onSale: row.isSale !== false,
      lastOrderAt:
        row.lastOrderAt != null ? String(row.lastOrderAt) : null,
      orderCountHint:
        row.orderCount != null
          ? Number(row.orderCount)
          : row.goodsQty != null
            ? Number(row.goodsQty)
            : null,
    }))
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
        thumbnailUrl: cafeImageFrom(detail, item),
      }
    },
  )

  return {
    cartId: cart.id != null ? Number(cart.id) : null,
    shopId: cart.shopId != null ? Number(cart.shopId) : undefined,
    items,
  }
}

/**
 * Snapshot cart lines with option menu ids so a cleared cart can be restored
 * after an abandoned quick-order checkout.
 */
export function mapCartRestoreLines(raw: unknown): StashedCartLine[] {
  const content = contentOf(raw) as Record<string, unknown> | null
  const cart = content && (content.cart as Record<string, unknown> | null)
  if (!cart) return []

  return asArray<Record<string, unknown>>(cart.goodsCartItems).map((item) => {
    const detail = (item.goodsDetail as Record<string, unknown>) || {}
    const byOption = new Map<number, number[]>()

    for (const opt of asArray<Record<string, unknown>>(item.goodsCartItemOptions)) {
      const optInfo = (opt.goodsOption as Record<string, unknown>) || {}
      const optionId = Number(
        opt.goodsOptionId ?? optInfo.id ?? opt.optionId ?? 0,
      )
      if (!optionId) continue
      const menuIds = byOption.get(optionId) ?? []
      for (const menu of asArray<Record<string, unknown>>(
        opt.goodsCartItemOptionMenus,
      )) {
        const menuInfo = (menu.goodsOptionMenu as Record<string, unknown>) || {}
        const menuId = Number(
          menu.goodsOptionMenuId ?? menuInfo.id ?? menu.menuId ?? 0,
        )
        if (menuId) menuIds.push(menuId)
      }
      if (menuIds.length) byOption.set(optionId, menuIds)
    }

    const options: SelectedOption[] = [...byOption.entries()].map(
      ([optionId, menuIds]) => ({ optionId, menuIds }),
    )

    return {
      goodsId: Number(detail.id),
      qty: Number(item.goodsQty ?? 0) || 1,
      options,
    }
  })
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

/** Categories with mobileUseYn=false (테스트, 그 외 사용안함, 이벤트 아카이브 등). */
export function hiddenCategoryIds(categories: CafeCategory[]): Set<number> {
  return new Set(categories.filter((c) => !c.mobileUseYn).map((c) => c.id))
}
