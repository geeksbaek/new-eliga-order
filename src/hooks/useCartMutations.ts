/**
 * Non-blocking cart mutations.
 * Optimistic UI first; rapid taps coalesce to the latest target qty only
 * (previous schedules/in-flight work is abandoned via generation tokens).
 */
import { useCallback, useRef } from 'react'
import {
  addToCart,
  clearCart,
  deleteCartItems,
  fetchCafeMenuDetail,
  fetchCart,
  updateCartQuantity,
} from '../api/eliga'
import {
  goodsQtyInCart,
  optimisticBumpGoods,
  optimisticSetLineQty,
  reapplyPendingGoodsDeltas,
} from '../lib/cart-optimistic'
import {
  defaultCartOptions,
  hasCompleteSingleDefaults,
} from '../lib/menu-options'
import type { CafeMenuItem, Cart } from '../lib/types'
import { useShop } from './useShop'

export type CartMutationError = {
  goodsId?: number
  cartItemId?: number
  error: unknown
  code?: 'OPTION_REQUIRED' | 'SYNC_FAILED'
}

type Options = {
  onError?: (err: CartMutationError) => void
}

const DEBOUNCE_MS = 180

export function useCartMutations(opts: Options = {}) {
  const onErrorRef = useRef(opts.onError)
  onErrorRef.current = opts.onError

  const { cart, setCartLocal, refreshCart, selectedShopId, getCart } =
    useShop()

  const goodsMeta = useRef(
    new Map<number, { name: string; price: number; displayId: number }>(),
  )

  /** Latest desired qty per goodsId (list stepper). */
  const targetGoodsQty = useRef(new Map<number, number>())
  const goodsGen = useRef(new Map<number, number>())
  const goodsTimers = useRef(new Map<number, number>())
  const goodsSyncing = useRef(new Set<number>())

  /** Latest desired qty per cart line (cart page). */
  const targetLineQty = useRef(new Map<number, number>())
  const lineGen = useRef(new Map<number, number>())
  const lineTimers = useRef(new Map<number, number>())
  const lineGoods = useRef(new Map<number, number>())

  const report = useCallback((err: CartMutationError) => {
    onErrorRef.current?.(err)
  }, [])

  const mergeServerCart = useCallback(
    (server: Cart, shopId: number) => {
      // Re-layer any goods still waiting on debounce (not yet sent)
      const pending = new Map<number, number>()
      const names = new Map<number, { name: string; price: number }>()
      for (const [gid, meta] of goodsMeta.current) {
        names.set(gid, { name: meta.name, price: meta.price })
      }
      for (const [gid, target] of targetGoodsQty.current) {
        if (goodsTimers.current.has(gid)) {
          const serverQ = goodsQtyInCart(server, gid)
          const delta = target - serverQ
          if (delta !== 0) pending.set(gid, delta)
        }
      }
      const sid = server.shopId ?? shopId
      if (pending.size === 0) {
        setCartLocal(server, sid)
        return
      }
      setCartLocal(reapplyPendingGoodsDeltas(server, pending, names), sid)
    },
    [setCartLocal],
  )

  /** Make server qty for goodsId equal `target` (absolute). */
  const applyAbsoluteGoodsQty = useCallback(
    async (shopId: number, goodsId: number, target: number) => {
      const server = await fetchCart(shopId)
      const lines = server.items.filter((l) => l.goodsId === goodsId)
      const total = lines.reduce((s, l) => s + l.qty, 0)
      const want = Math.max(0, target)
      if (want === total) return server

      if (want > total) {
        const need = want - total
        if (lines.length === 0 || server.cartId == null) {
          const meta = goodsMeta.current.get(goodsId)
          if (!meta) {
            throw Object.assign(new Error('메뉴 정보가 없습니다'), {
              code: 'SYNC_FAILED' as const,
            })
          }
          const detail = await fetchCafeMenuDetail(meta.displayId)
          const variant =
            detail.variants.find((v) => v.goodsId === goodsId && !v.soldOut) ||
            detail.variants.find((v) => !v.soldOut) ||
            detail.variants[0]
          if (!variant || variant.soldOut) {
            throw Object.assign(new Error('옵션 선택이 필요합니다'), {
              code: 'OPTION_REQUIRED' as const,
            })
          }
          if (!hasCompleteSingleDefaults(variant)) {
            throw Object.assign(new Error('옵션 선택이 필요합니다'), {
              code: 'OPTION_REQUIRED' as const,
            })
          }
          await addToCart({
            shopId,
            goodsId: variant.goodsId,
            qty: need,
            options: defaultCartOptions(variant),
          })
        } else {
          await updateCartQuantity({
            cartId: server.cartId,
            cartItemId: lines[0].cartItemId,
            goodsQty: lines[0].qty + need,
          })
        }
      } else {
        if (server.cartId == null) return server
        let remove = total - want
        for (const line of lines) {
          if (remove <= 0) break
          if (line.qty <= remove) {
            await deleteCartItems({
              cartId: server.cartId,
              cartItemIds: [line.cartItemId],
            })
            remove -= line.qty
          } else {
            await updateCartQuantity({
              cartId: server.cartId,
              cartItemId: line.cartItemId,
              goodsQty: line.qty - remove,
            })
            remove = 0
          }
        }
      }
      return fetchCart(shopId)
    },
    [],
  )

  const runGoodsSync = useCallback(
    async (goodsId: number, shopId: number, gen: number) => {
      if (goodsGen.current.get(goodsId) !== gen) return
      const target = targetGoodsQty.current.get(goodsId)
      if (target == null) return
      if (goodsSyncing.current.has(goodsId)) {
        // Another sync still running — it will re-check target on exit
        return
      }
      goodsSyncing.current.add(goodsId)
      try {
        while (goodsGen.current.get(goodsId) === gen) {
          const latest = targetGoodsQty.current.get(goodsId)
          if (latest == null) break
          // Capture gen at start of this attempt
          const attemptGen = goodsGen.current.get(goodsId) ?? gen
          try {
            const fresh = await applyAbsoluteGoodsQty(shopId, goodsId, latest)
            if (goodsGen.current.get(goodsId) !== attemptGen) {
              // Superseded — loop will exit or newer run will take over
              continue
            }
            const still = targetGoodsQty.current.get(goodsId)
            if (still != null && still !== latest) {
              // Target moved during network; apply again with same gen ownership
              continue
            }
            targetGoodsQty.current.delete(goodsId)
            mergeServerCart(fresh, shopId)
            break
          } catch (e) {
            if (goodsGen.current.get(goodsId) !== attemptGen) return
            targetGoodsQty.current.delete(goodsId)
            await refreshCart({ silent: true, shopId })
            const code =
              e &&
              typeof e === 'object' &&
              'code' in e &&
              (e as { code?: string }).code === 'OPTION_REQUIRED'
                ? 'OPTION_REQUIRED'
                : 'SYNC_FAILED'
            report({ goodsId, error: e, code })
            break
          }
        }
      } finally {
        goodsSyncing.current.delete(goodsId)
        // If a newer gen scheduled while we finished, fire it
        const curGen = goodsGen.current.get(goodsId)
        if (
          curGen != null &&
          curGen !== gen &&
          targetGoodsQty.current.has(goodsId)
        ) {
          void runGoodsSync(goodsId, shopId, curGen)
        }
      }
    },
    [applyAbsoluteGoodsQty, mergeServerCart, refreshCart, report],
  )

  const scheduleGoodsSync = useCallback(
    (goodsId: number, shopId: number) => {
      const prevTimer = goodsTimers.current.get(goodsId)
      if (prevTimer != null) window.clearTimeout(prevTimer)

      const gen = (goodsGen.current.get(goodsId) ?? 0) + 1
      goodsGen.current.set(goodsId, gen)

      const timer = window.setTimeout(() => {
        goodsTimers.current.delete(goodsId)
        void runGoodsSync(goodsId, shopId, gen)
      }, DEBOUNCE_MS)

      goodsTimers.current.set(goodsId, timer)
    },
    [runGoodsSync],
  )

  const bumpMenuQty = useCallback(
    (
      item: CafeMenuItem,
      delta: number,
      shopId: number,
    ): { ok: true } | { ok: false; reason: 'soldout' | 'no-goods' | 'noop' } => {
      if (item.soldOut) return { ok: false, reason: 'soldout' }
      if (item.goodsId == null) return { ok: false, reason: 'no-goods' }
      const goodsId = item.goodsId

      goodsMeta.current.set(goodsId, {
        name: item.name,
        price: item.price,
        displayId: item.displayId,
      })

      const before = getCart(shopId)
      const after = optimisticBumpGoods(before, item, delta)
      const prevQ = goodsQtyInCart(before, goodsId)
      const nextQ = goodsQtyInCart(after, goodsId)
      if (prevQ === nextQ) return { ok: false, reason: 'noop' }

      setCartLocal(after, shopId)
      targetGoodsQty.current.set(goodsId, nextQ)
      scheduleGoodsSync(goodsId, shopId)
      return { ok: true }
    },
    [getCart, setCartLocal, scheduleGoodsSync],
  )

  const scheduleLineSync = useCallback(
    (cartItemId: number, shopId: number) => {
      const prevTimer = lineTimers.current.get(cartItemId)
      if (prevTimer != null) window.clearTimeout(prevTimer)

      const gen = (lineGen.current.get(cartItemId) ?? 0) + 1
      lineGen.current.set(cartItemId, gen)

      const timer = window.setTimeout(() => {
        lineTimers.current.delete(cartItemId)
        void (async () => {
          if (lineGen.current.get(cartItemId) !== gen) return
          const want = targetLineQty.current.get(cartItemId)
          if (want == null) return
          try {
            // Loop until target stable for this gen
            while (lineGen.current.get(cartItemId) === gen) {
              const latestWant = targetLineQty.current.get(cartItemId)
              if (latestWant == null) return

              let cartId = getCart(shopId).cartId
              let lineId = cartItemId
              const goodsId = lineGoods.current.get(cartItemId)

              if (cartId == null || cartItemId < 0 || goodsId != null) {
                const server = await fetchCart(shopId)
                if (lineGen.current.get(cartItemId) !== gen) return
                cartId = server.cartId
                const match =
                  (goodsId != null
                    ? server.items.find((l) => l.goodsId === goodsId)
                    : null) ||
                  server.items.find((l) => l.cartItemId === cartItemId)
                if (!match || cartId == null) {
                  if (latestWant <= 0) {
                    targetLineQty.current.delete(cartItemId)
                    mergeServerCart(server, shopId)
                    return
                  }
                  throw new Error('장바구니 항목을 찾을 수 없습니다')
                }
                lineId = match.cartItemId
              }

              if (lineGen.current.get(cartItemId) !== gen) return

              if (latestWant <= 0) {
                await deleteCartItems({
                  cartId: cartId!,
                  cartItemIds: [lineId],
                })
              } else {
                await updateCartQuantity({
                  cartId: cartId!,
                  cartItemId: lineId,
                  goodsQty: latestWant,
                })
              }

              if (lineGen.current.get(cartItemId) !== gen) return
              const still = targetLineQty.current.get(cartItemId)
              if (still != null && still !== latestWant) continue

              targetLineQty.current.delete(cartItemId)
              const fresh = await fetchCart(shopId)
              if (lineGen.current.get(cartItemId) !== gen) return
              mergeServerCart(fresh, shopId)
              return
            }
          } catch (e) {
            if (lineGen.current.get(cartItemId) !== gen) return
            targetLineQty.current.delete(cartItemId)
            await refreshCart({ silent: true, shopId })
            report({ cartItemId, error: e, code: 'SYNC_FAILED' })
          }
        })()
      }, DEBOUNCE_MS)

      lineTimers.current.set(cartItemId, timer)
    },
    [getCart, mergeServerCart, refreshCart, report],
  )

  const changeLineQty = useCallback(
    (cartItemId: number, goodsQty: number, shopIdArg?: number) => {
      const shopId = shopIdArg ?? selectedShopId
      if (shopId == null) return

      const snap = getCart(shopId).items.find((l) => l.cartItemId === cartItemId)
      if (snap) lineGoods.current.set(cartItemId, snap.goodsId)

      setCartLocal(
        (prev) => optimisticSetLineQty(prev, cartItemId, goodsQty),
        shopId,
      )
      targetLineQty.current.set(cartItemId, Math.max(0, goodsQty))
      scheduleLineSync(cartItemId, shopId)
    },
    [selectedShopId, getCart, setCartLocal, scheduleLineSync],
  )

  const removeLine = useCallback(
    (cartItemId: number) => changeLineQty(cartItemId, 0),
    [changeLineQty],
  )

  /** Drop every line in the shop cart (optimistic, then server clear). */
  const clearAllLines = useCallback(
    async (shopIdArg?: number) => {
      const shopId = shopIdArg ?? selectedShopId
      if (shopId == null) return

      const current = getCart(shopId)
      if (current.items.length === 0) return

      // Abandon in-flight / debounced line qty syncs so they cannot re-fill
      for (const item of current.items) {
        const timer = lineTimers.current.get(item.cartItemId)
        if (timer != null) window.clearTimeout(timer)
        lineTimers.current.delete(item.cartItemId)
        lineGen.current.set(
          item.cartItemId,
          (lineGen.current.get(item.cartItemId) ?? 0) + 1,
        )
        targetLineQty.current.delete(item.cartItemId)
        lineGoods.current.delete(item.cartItemId)
      }

      setCartLocal(
        {
          cartId: current.cartId,
          shopId,
          items: [],
        },
        shopId,
      )

      try {
        const fresh = await clearCart(shopId)
        setCartLocal({ ...fresh, shopId: fresh.shopId ?? shopId }, shopId)
      } catch (e) {
        await refreshCart({ silent: true, shopId, force: true })
        report({ error: e, code: 'SYNC_FAILED' })
      }
    },
    [selectedShopId, getCart, setCartLocal, refreshCart, report],
  )

  const addFromDetail = useCallback(
    async (params: {
      shopId: number
      goodsId: number
      name: string
      price: number
      displayId: number
      qty: number
      options: Parameters<typeof addToCart>[0]['options']
    }) => {
      goodsMeta.current.set(params.goodsId, {
        name: params.name,
        price: params.price,
        displayId: params.displayId,
      })
      setCartLocal(
        (prev) =>
          optimisticBumpGoods(
            prev,
            {
              goodsId: params.goodsId,
              name: params.name,
              price: params.price,
            },
            params.qty,
          ),
        params.shopId,
      )
      try {
        await addToCart({
          shopId: params.shopId,
          goodsId: params.goodsId,
          qty: params.qty,
          options: params.options,
        })
        const fresh = await fetchCart(params.shopId)
        mergeServerCart(fresh, params.shopId)
      } catch (e) {
        await refreshCart({ silent: true, shopId: params.shopId })
        throw e
      }
    },
    [setCartLocal, mergeServerCart, refreshCart],
  )

  return {
    cart,
    bumpMenuQty,
    changeLineQty,
    removeLine,
    clearAllLines,
    addFromDetail,
  }
}
