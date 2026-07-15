import type { Shop, ShopType } from './types'

/** Fixed kakao campus shops from eliga-order skill. */
export const KNOWN_SHOPS: ReadonlyArray<{
  shopId: number
  name: string
  type: ShopType
}> = [
  { shopId: 7, name: '춘식도락(B1F)', type: 'CAFETERIA' },
  { shopId: 3, name: '춘식도락 with in the box(4F)', type: 'CAFE' },
  { shopId: 4, name: 'kafé 3F', type: 'CAFE' },
  { shopId: 5, name: 'kafé 5F', type: 'CAFE' },
  { shopId: 8, name: 'kafé 5F b', type: 'CAFE' },
]

/** Default cafe when user does not specify a floor. */
export const DEFAULT_CAFE_SHOP_ID = 5

/** Cafeteria is view-only (no cart/order). */
export const CAFETERIA_SHOP_ID = 7

export function isCafeShop(type: ShopType | undefined | null): boolean {
  if (!type) return false
  return String(type).toUpperCase() === 'CAFE'
}

export function isCafeteriaShop(type: ShopType | undefined | null): boolean {
  if (!type) return false
  const t = String(type).toUpperCase()
  return t === 'CAFETERIA' || t === 'RESTAURANT'
}

/** Cart / order only allowed for cafe shops. */
export function canOrderFromShop(
  shop: Pick<Shop, 'type' | 'shopId'> | null | undefined,
): boolean {
  if (!shop) return false
  if (shop.shopId === CAFETERIA_SHOP_ID) return false
  if (isCafeteriaShop(shop.type)) return false
  return isCafeShop(shop.type)
}

export function canViewDiningMenu(
  shop: Pick<Shop, 'type' | 'shopId'> | null | undefined,
): boolean {
  if (!shop) return false
  return shop.shopId === CAFETERIA_SHOP_ID || isCafeteriaShop(shop.type)
}

export function resolveShopType(
  shopId: number,
  apiType?: ShopType | null,
): ShopType {
  if (apiType) return apiType
  const known = KNOWN_SHOPS.find((s) => s.shopId === shopId)
  return known?.type ?? 'CAFE'
}

export function soldOutBlocksOrder(soldOut: boolean | undefined | null): boolean {
  return Boolean(soldOut)
}

/**
 * Pick sticky last-used shop, else default cafe for ordering contexts.
 * Cafeteria stays selectable for menu viewing.
 */
export function preferShopId(
  lastUsed: number | null | undefined,
  available: Array<{ shopId: number }>,
): number {
  if (
    lastUsed != null &&
    available.some((s) => s.shopId === lastUsed)
  ) {
    return lastUsed
  }
  if (available.some((s) => s.shopId === DEFAULT_CAFE_SHOP_ID)) {
    return DEFAULT_CAFE_SHOP_ID
  }
  return available[0]?.shopId ?? DEFAULT_CAFE_SHOP_ID
}

/**
 * Cafe tab chips / home recent sources.
 * Always whitelist known CAFE ids so API mislabels (e.g. shop 7 as CAFE)
 * never surface the cafeteria 춘식도락(B1F).
 */
export function listCafeShops(
  shops: Array<{ shopId: number; name: string; type?: string }>,
): Array<{ shopId: number; name: string; type: ShopType }> {
  const live = new Map(shops.map((s) => [s.shopId, s]))
  return KNOWN_SHOPS.filter((s) => s.type === 'CAFE').map((k) => {
    const hit = live.get(k.shopId)
    return {
      shopId: k.shopId,
      name: hit?.name?.trim() || k.name,
      type: 'CAFE' as ShopType,
    }
  })
}
