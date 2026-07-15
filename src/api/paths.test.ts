import { describe, expect, it } from 'vitest'
import {
  BASE_HOST,
  SVC_HOST,
  BRAND_CODE,
  PROXY_BASE,
  PROXY_SVC,
  isLiftHost,
  getCanonicalAppUrl,
} from './client'
import {
  buildCartAddBody,
  buildOrderPayload,
} from '../lib/order-payload'

/**
 * Static contract checks: shipped client targets skill hosts/paths
 * and encodes cafe order constraints.
 */
describe('API contract wiring', () => {
  it('targets base.eligaorder.com and svc.eligaorder.com', () => {
    expect(BASE_HOST).toBe('https://base.eligaorder.com')
    expect(SVC_HOST).toBe('https://svc.eligaorder.com')
    expect(BRAND_CODE).toBe('kakao')
    expect(PROXY_BASE).toBe('/__eliga-base')
    expect(PROXY_SVC).toBe('/__eliga-svc')
  })

  it('detects LIFT host for CSP redirect gate', () => {
    expect(isLiftHost('lift.onkakao.net')).toBe(true)
    expect(isLiftHost('localhost')).toBe(false)
    expect(getCanonicalAppUrl()).toMatch(/^https?:\/\//)
  })

  it('cart and order payloads use production field names', () => {
    const cartBody = buildCartAddBody({
      shopId: 5,
      goodsId: 568,
      qty: 1,
      options: [],
    })
    expect(cartBody.cartType).toBe('GENERAL')
    expect(Array.isArray(cartBody.goodsCartItems)).toBe(true)

    const order = buildOrderPayload({
      shopId: 5,
      cartId: 1,
      paymentReasonId: 13,
      items: [
        {
          cartItemId: 1,
          goodsId: 568,
          name: 'test',
          qty: 1,
          price: 500,
          options: [],
        },
      ],
    })
    expect(order.goodsOrderType).toBe('SHOP_PICKUP')
    expect(order.payType).toBe('INTERNAL')
    expect(order.orderType).toBe('AUTO')
  })
})
