import { describe, expect, it } from 'vitest'
import {
  BASE_HOST,
  SVC_HOST,
  BRAND_CODE,
  PROXY_ENTRY,
  proxyUrl,
} from './client'
import {
  buildCartAddBody,
  buildOrderPayload,
} from '../lib/order-payload'

describe('API contract wiring', () => {
  it('targets base.eligaorder.com and svc.eligaorder.com', () => {
    expect(BASE_HOST).toBe('https://base.eligaorder.com')
    expect(SVC_HOST).toBe('https://svc.eligaorder.com')
    expect(BRAND_CODE).toBe('kakao')
    expect(PROXY_ENTRY).toBe('/api/proxy')
  })

  it('builds single-endpoint proxy URLs', () => {
    expect(proxyUrl('base', 'space', { brandCode: 'kakao' })).toBe(
      '/api/proxy?to=base&path=space&brandCode=kakao',
    )
    expect(proxyUrl('svc', 'venus/customer/sign-in')).toBe(
      '/api/proxy?to=svc&path=venus%2Fcustomer%2Fsign-in',
    )
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
