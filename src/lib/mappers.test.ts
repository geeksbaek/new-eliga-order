import { describe, expect, it } from 'vitest'
import {
  hiddenCategoryIds,
  isTestCafeDisplay,
  mapCafeCategories,
  mapCafeMenu,
  mapCafeMenuDetail,
  mapCart,
  mapCartRestoreLines,
  mapPaymentReasons,
  mapShops,
} from './mappers'
import type { CafeCategory } from './types'

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
    expect(items[0].thumbnailUrl).toBeNull()
    expect(items[0].categoryId).toBe(1)
  })

  it('maps cafe menu thumbnailPath', () => {
    const raw = {
      content: [
        {
          id: 2,
          name: { ko: '라떼' },
          categoryName: { ko: 'Coffee' },
          categoryId: 1,
          thumbnailPath: 'images/goods/latte.jpg',
          repGoods: {
            id: 11,
            displayName: { ko: 'HOT' },
            soldOutYn: false,
            goodsPricePlans: [{ payMethodType: 'IDCARD', price: 3500 }],
          },
        },
      ],
    }
    const items = mapCafeMenu(raw)
    expect(items[0].thumbnailUrl).toContain('latte.jpg')
  })

  it('filters mobileUseYn categories, flags, and 0원 goods', () => {
    const raw = {
      content: [
        {
          id: 10,
          name: { ko: '아메리카노' },
          categoryName: { ko: 'Coffee' },
          categoryId: 25,
          repGoods: {
            id: 100,
            soldOutYn: false,
            goodsPricePlans: [
              { payMethodType: 'NORMAL', price: 3000 },
              { payMethodType: 'IDCARD', price: 2500 },
            ],
          },
        },
        // 0원 = hide (ops test stubs)
        {
          id: 187,
          name: { ko: 'Test상품(지우지 말아주세요)' },
          categoryName: { ko: 'Coffee' },
          categoryId: 25,
          repGoods: {
            id: 283,
            soldOutYn: false,
            goodsPricePlans: [
              { payMethodType: 'NORMAL', price: 0 },
              { payMethodType: 'IDCARD', price: 0 },
            ],
          },
        },
        {
          id: 73,
          name: { ko: '테스트 상품 (지우지말아주세요)' },
          categoryName: { ko: 'Coffee' },
          categoryId: 25,
          repGoods: {
            id: 73,
            soldOutYn: false,
            goodsPricePlans: [
              { payMethodType: 'NORMAL', price: 0 },
              { payMethodType: 'IDCARD', price: 0 },
            ],
          },
        },
        // testYn flag
        {
          id: 12,
          name: { ko: '플래그 메뉴' },
          categoryName: { ko: 'Coffee' },
          categoryId: 25,
          testYn: true,
          repGoods: {
            id: 102,
            soldOutYn: false,
            goodsPricePlans: [{ payMethodType: 'IDCARD', price: 100 }],
          },
        },
        // displayYn false
        {
          id: 13,
          name: { ko: '숨김 메뉴' },
          categoryName: { ko: 'Coffee' },
          categoryId: 25,
          displayYn: false,
          repGoods: {
            id: 103,
            soldOutYn: false,
            goodsPricePlans: [{ payMethodType: 'IDCARD', price: 100 }],
          },
        },
        // mobileUseYn=false category
        {
          id: 15,
          name: { ko: '일반 메뉴' },
          categoryName: { ko: '테스트' },
          categoryId: 34,
          repGoods: {
            id: 105,
            soldOutYn: false,
            goodsPricePlans: [{ payMethodType: 'IDCARD', price: 100 }],
          },
        },
      ],
    }
    const hidden = hiddenCategoryIds([
      { id: 25, name: 'Coffee', mobileUseYn: true, goodsCount: 3 },
      { id: 34, name: '테스트', mobileUseYn: false, goodsCount: 1 },
    ])
    const items = mapCafeMenu(raw, hidden)
    expect(items.map((i) => i.name)).toEqual(['아메리카노'])
    expect(isTestCafeDisplay({ testYn: true }, {})).toBe(true)
    expect(
      isTestCafeDisplay(
        {},
        {
          goodsPricePlans: [
            { payMethodType: 'NORMAL', price: 0 },
            { payMethodType: 'IDCARD', price: 0 },
          ],
        },
      ),
    ).toBe(true)
    expect(
      isTestCafeDisplay(
        {},
        {
          goodsPricePlans: [
            { payMethodType: 'NORMAL', price: 3700 },
            { payMethodType: 'IDCARD', price: 3200 },
          ],
        },
      ),
    ).toBe(false)
    // recent/popular rows have no price plans — must keep
    expect(
      isTestCafeDisplay(
        {
          displayId: 210,
          goodsId: 293,
          name: { ko: '혼합 아이스크림' },
          isSale: true,
          stockEmptyYn: false,
        },
        {},
      ),
    ).toBe(false)
  })

  it('hides only mobileUseYn=false categories', () => {
    const cats: CafeCategory[] = [
      { id: 25, name: 'Coffee', mobileUseYn: true, goodsCount: 3 },
      { id: 34, name: '테스트', mobileUseYn: false, goodsCount: 2 },
      { id: 32, name: '그 외 (사용 안함)', mobileUseYn: false, goodsCount: 1 },
    ]
    expect([...hiddenCategoryIds(cats)].sort()).toEqual([32, 34])
  })

  it('maps mobileUseYn from API only', () => {
    const cats = mapCafeCategories({
      content: [
        { id: 25, name: { ko: 'Coffee' }, mobileUseYn: true },
        { id: 34, name: { ko: '테스트' }, mobileUseYn: false },
        // name looks like test but mobileUseYn true → keep (property only)
        { id: 99, name: { ko: 'QA 이벤트' }, mobileUseYn: true },
      ],
    })
    expect(cats.find((c) => c.id === 25)?.mobileUseYn).toBe(true)
    expect(cats.find((c) => c.id === 34)?.mobileUseYn).toBe(false)
    expect(cats.find((c) => c.id === 99)?.mobileUseYn).toBe(true)
  })

  it('maps menu detail variants and options', () => {
    const raw = {
      content: {
        id: 189,
        labelOptionType: 'BEST',
        thumbnailPath: 'images/goods/americano.jpg',
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
    expect(detail.thumbnailUrl).toContain('americano.jpg')
    expect(detail.variants[0].thumbnailUrl).toContain('americano.jpg')
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
          thumbnailUrl: null,
        },
      ],
    })
  })

  it('maps cart restore lines with option menu ids', () => {
    const raw = {
      content: {
        cart: {
          id: 1,
          shopId: 5,
          goodsCartItems: [
            {
              id: 10,
              goodsQty: 2,
              goodsDetail: { id: 568, name: { ko: '아메' } },
              goodsCartItemOptions: [
                {
                  goodsOptionId: 40,
                  goodsOption: { id: 40, name: { ko: '컵' } },
                  goodsCartItemOptionMenus: [
                    {
                      goodsOptionMenuId: 68,
                      goodsOptionMenu: { id: 68, name: { ko: '일회용컵' } },
                    },
                  ],
                },
              ],
            },
          ],
        },
      },
    }
    expect(mapCartRestoreLines(raw)).toEqual([
      {
        goodsId: 568,
        qty: 2,
        options: [{ optionId: 40, menuIds: [68] }],
      },
    ])
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
