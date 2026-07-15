import { describe, expect, it } from 'vitest'
import {
  assertOrderConfirmed,
  buildCartAddBody,
  buildCartAddBodiesFromBatch,
  buildCartDeleteBody,
  buildCartQuantityBody,
  buildOrderPayload,
  pickDefaultPaymentReasonId,
} from './order-payload'
import type { CartItem } from './types'

/** Fixture shaped like skill cart-list items. */
const cartItems: CartItem[] = [
  {
    cartItemId: 1188090,
    goodsId: 299,
    name: '허니요거베리',
    qty: 1,
    price: 2000,
    options: [],
  },
  {
    cartItemId: 1188091,
    goodsId: 568,
    name: '아메리카노 HOT',
    qty: 2,
    price: 500,
    options: [{ option: '컵', value: '매장컵' }],
  },
]

describe('order-payload', () => {
  it('builds order body matching eliga-api.sh fields', () => {
    const payload = buildOrderPayload({
      shopId: 5,
      cartId: 555754,
      paymentReasonId: 13,
      items: cartItems,
    })

    expect(payload.deviceType).toBe('MOBILE')
    expect(payload.orderType).toBe('AUTO')
    expect(payload.payType).toBe('INTERNAL')
    expect(payload.brandCode).toBe('kakao')
    expect(payload.shopId).toBe(5)
    expect(payload.cartId).toBe(555754)
    expect(payload.goodsOrderType).toBe('SHOP_PICKUP')
    expect(payload.paymentReasonId).toBe(13)
    expect(payload.totalUsedPoint).toBe(0)
    // 2000*1 + 500*2 = 3000
    expect(payload.totalUnitPrice).toBe(3000)
    expect(payload.totalSalesPrice).toBe(3000)
    expect(payload.orderItems).toEqual([
      {
        goodsId: 299,
        goodsQty: 1,
        salesPrice: 2000,
        unitPrice: 2000,
        goodsCartItemId: 1188090,
        goodsOrderItemOptions: [],
      },
      {
        goodsId: 568,
        goodsQty: 2,
        salesPrice: 1000,
        unitPrice: 500,
        goodsCartItemId: 1188091,
        goodsOrderItemOptions: [],
      },
    ])
  })

  it('rejects empty cart / missing cartId / missing payment reason', () => {
    expect(() =>
      buildOrderPayload({
        shopId: 5,
        cartId: 0,
        paymentReasonId: 13,
        items: cartItems,
      }),
    ).toThrow(/cartId/)
    expect(() =>
      buildOrderPayload({
        shopId: 5,
        cartId: 1,
        paymentReasonId: 0,
        items: cartItems,
      }),
    ).toThrow(/paymentReasonId/)
    expect(() =>
      buildOrderPayload({
        shopId: 5,
        cartId: 1,
        paymentReasonId: 13,
        items: [],
      }),
    ).toThrow(/orderItems/)
  })

  it('builds cart-add body with goodsCartItemOptions like fmt.py', () => {
    const body = buildCartAddBody({
      shopId: 5,
      goodsId: 568,
      qty: 1,
      options: [{ optionId: 40, menuId: 68 }],
    })
    expect(body).toEqual({
      shopId: 5,
      cartType: 'GENERAL',
      generalCartId: null,
      goodsCartItems: [
        {
          goodsId: 568,
          goodsQty: 1,
          goodsCartItemOptions: [
            {
              goodsOptionId: 40,
              goodsCartItemOptionMenus: [{ goodsOptionMenuId: 68 }],
            },
          ],
        },
      ],
    })
  })

  it('builds batch cart-add bodies from simplified skill input', () => {
    const bodies = buildCartAddBodiesFromBatch({
      shopId: 5,
      items: [
        { goodsId: 299, qty: 1, options: [] },
        { goodsId: 568, qty: 2, options: [{ optionId: 40, menuId: 68 }] },
      ],
    })
    expect(bodies).toHaveLength(2)
    expect(bodies[0].goodsCartItems).toBeDefined()
    expect(
      (bodies[1].goodsCartItems as Array<{ goodsQty: number }>)[0].goodsQty,
    ).toBe(2)
  })

  it('builds quantity and delete bodies', () => {
    expect(
      buildCartQuantityBody({
        cartId: 555754,
        cartItemId: 1188090,
        goodsQty: 2,
      }),
    ).toEqual({ cartId: 555754, cartItemId: 1188090, goodsQty: 2 })
    expect(
      buildCartDeleteBody({ cartId: 555754, cartItemIds: [1188090] }),
    ).toEqual({ id: 555754, goodsCartItemIds: [1188090] })
  })

  it('defaults payment reason to 개인결제 when present', () => {
    const reasons = [
      { id: 14, reason: '1on1 (조직장 only, 음료 2잔)' },
      { id: 13, reason: '개인결제' },
    ]
    expect(pickDefaultPaymentReasonId(reasons)).toBe(13)
    expect(pickDefaultPaymentReasonId([{ id: 99, reason: '기타' }])).toBe(99)
    expect(pickDefaultPaymentReasonId([])).toBeNull()
  })

  it('enforces explicit order confirmation gate', () => {
    expect(() => assertOrderConfirmed(false)).toThrow(/최종 확인/)
    expect(() => assertOrderConfirmed(true)).not.toThrow()
  })
})
