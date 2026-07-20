import type { CafeMenuItem, Cart, CartItem } from './types'

/** Temp cart line ids are negative so they never collide with server ids. */
export function tempCartItemId(): number {
  return -Math.floor(Date.now() + Math.random() * 1000)
}

export function isTempCartItemId(id: number): boolean {
  return id < 0
}

export function goodsQtyInCart(cart: Cart, goodsId: number): number {
  return cart.items
    .filter((l) => l.goodsId === goodsId)
    .reduce((s, l) => s + (Number(l.qty) || 0), 0)
}

/** Apply ±qty for a goods line on the local cart (list stepper). */
export function optimisticBumpGoods(
  cart: Cart,
  item: Pick<CafeMenuItem, 'goodsId' | 'name' | 'price'>,
  delta: number,
): Cart {
  if (item.goodsId == null || delta === 0) return cart
  const goodsId = item.goodsId
  const lines = cart.items.filter((l) => l.goodsId === goodsId)
  const total = lines.reduce((s, l) => s + l.qty, 0)
  const nextTotal = Math.max(0, total + delta)
  if (nextTotal === total) return cart

  if (nextTotal === 0) {
    return {
      ...cart,
      items: cart.items.filter((l) => l.goodsId !== goodsId),
    }
  }

  if (lines.length === 0) {
    const line: CartItem = {
      cartItemId: tempCartItemId(),
      goodsId,
      name: item.name,
      qty: nextTotal,
      price: item.price,
      options: [],
      thumbnailUrl:
        'thumbnailUrl' in item
          ? ((item as CafeMenuItem).thumbnailUrl ?? null)
          : null,
    }
    return { ...cart, items: [...cart.items, line] }
  }

  // Prefer mutating the first line; drop extra lines of same goods if reducing
  const primary = lines[0]
  const others = cart.items.filter((l) => l.goodsId !== goodsId)
  if (nextTotal > 0) {
    return {
      ...cart,
      items: [
        ...others,
        { ...primary, qty: nextTotal },
        // collapse multi-lines of same goods into one for display
      ],
    }
  }
  return { ...cart, items: others }
}

export function optimisticSetLineQty(
  cart: Cart,
  cartItemId: number,
  goodsQty: number,
): Cart {
  if (goodsQty <= 0) {
    return {
      ...cart,
      items: cart.items.filter((l) => l.cartItemId !== cartItemId),
    }
  }
  return {
    ...cart,
    items: cart.items.map((l) =>
      l.cartItemId === cartItemId ? { ...l, qty: goodsQty } : l,
    ),
  }
}

export function optimisticRemoveLine(cart: Cart, cartItemId: number): Cart {
  return {
    ...cart,
    items: cart.items.filter((l) => l.cartItemId !== cartItemId),
  }
}

/**
 * After a silent server fetch, re-apply pending net deltas so in-flight
 * taps are not wiped by the response.
 */
export function reapplyPendingGoodsDeltas(
  serverCart: Cart,
  pending: ReadonlyMap<number, number>,
  nameByGoods: ReadonlyMap<number, { name: string; price: number }>,
): Cart {
  let next = serverCart
  for (const [goodsId, delta] of pending) {
    if (!delta) continue
    const meta = nameByGoods.get(goodsId) ?? {
      name: `메뉴 ${goodsId}`,
      price: 0,
    }
    next = optimisticBumpGoods(
      next,
      { goodsId, name: meta.name, price: meta.price },
      delta,
    )
  }
  return next
}
