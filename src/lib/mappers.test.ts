import { describe, expect, it } from 'vitest'
import {
  mapCafeMenu,
  mapCafeMenuDetail,
  mapCart,
  mapPaymentReasons,
  mapShops,
} from './mappers'

describe('mappers from skill-shaped API fixtures', () => {
  it('maps shops from /shop/me content', () => {
    const raw = {
      content: [
        {
          id: 5,
          name: { ko: 'kafé 5F', en: 'kafe 5F' },
          type: 'CAFE',
          openYn: true,
        },
        {
          id: 7,
          name: { ko: '춘식도락(B1F)' },
          type: 'CAFETERIA',
          openYn: false,
        },
      ],
    }
    expect(mapShops(raw)).toEqual([
      { shopId: 5, name: 'kafé 5F', type: 'CAFE', open: true },
      { shopId: 7, name: '춘식도락(B1F)', type: 'CAFETERIA', open: false },
    ])
  })

  it('stringifies i18n description objects (React cannot render {ko,en})', () => {
    const raw = {
      content: [
        {
          id: 1,
          name: { ko: '아메리카노' },
          categoryName: { ko: 'Coffee' },
          categoryId: 1,
          labelOptionType: 'BEST',
          repGoods: {
            id: 10,
            displayName: { ko: 'HOT' },
            description: { ko: '진한 에스프레소', en: 'Espresso' },
            nutrition: { ko: '탄수화물 0g' },
            soldOutYn: false,
            goodsPricePlans: [
              { payMethodType: 'NORMAL', price: 3000 },
              { payMethodType: 'IDCARD', price: 2500 },
            ],
          },
        },
      ],
    }
    const items = mapCafeMenu(raw)
    expect(items[0].description).toBe('진한 에스프레소')
    expect(items[0].nutrition).toBe('탄수화물 0g')
    expect(typeof items[0].description).toBe('string')
  })

  it('maps menu detail variants and options', () => {
    const raw = {
      content: {
        id: 189,
        labelOptionType: 'BEST',
        goods: [
          {
            id: 568,
            shopId: 5,
            name: { ko: '아메리카노 HOT' },
            displayName: { ko: 'HOT' },
            soldOutYn: false,
            goodsPricePlans: [
              { payMethodType: 'NORMAL', price: 3000 },
              { payMethodType: 'IDCARD', price: 2500 },
            ],
            goodsOptions: [
              {
                id: 40,
                name: { ko: '컵' },
                activationType: true,
                multiSelectYn: false,
                goodsOptionMenus: [
                  {
                    id: 68,
                    name: { ko: '매장컵' },
                    goodsOptionMenuPrices: [
                      { payMethodType: 'NORMAL', optionPrice: 0 },
                      { payMethodType: 'IDCARD', optionPrice: 0 },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      },
    }
    const detail = mapCafeMenuDetail(raw)
    expect(detail.displayId).toBe(189)
    expect(detail.variants[0].goodsId).toBe(568)
    expect(detail.variants[0].price).toBe(500)
    expect(detail.variants[0].options[0].optionId).toBe(40)
    expect(detail.variants[0].options[0].menus[0].menuId).toBe(68)
  })

  it('maps cart list envelope', () => {
    const raw = {
      content: {
        cart: {
          id: 555754,
          shopId: 5,
          goodsCartItems: [
            {
              id: 1188090,
              goodsQty: 1,
              goodsDetail: {
                id: 299,
                name: { ko: '허니요거베리' },
                goodsPricePlans: [
                  { payMethodType: 'NORMAL', price: 4500 },
                  { payMethodType: 'IDCARD', price: 2500 },
                ],
              },
              goodsCartItemOptions: [],
            },
          ],
        },
      },
    }
    expect(mapCart(raw)).toEqual({
      cartId: 555754,
      shopId: 5,
      items: [
        {
          cartItemId: 1188090,
          goodsId: 299,
          name: '허니요거베리',
          qty: 1,
          price: 2000,
          options: [],
        },
      ],
    })
  })

  it('filters inactive payment reasons', () => {
    const raw = {
      content: [
        { id: 13, reason: { ko: '개인결제' }, useYn: true },
        { id: 99, reason: { ko: '숨김' }, useYn: false },
      ],
    }
    expect(mapPaymentReasons(raw)).toEqual([{ id: 13, reason: '개인결제' }])
  })
})
