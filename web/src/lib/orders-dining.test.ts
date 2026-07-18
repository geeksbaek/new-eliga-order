import { describe, expect, it } from 'vitest'
import {
  mapCafeQuickItems,
  mapDiningMenu,
  mapOrderHistory,
} from './mappers'
import {
  ELIGA_CDN_BASE,
  mediaUrl,
  orderStatusLabel,
  parseKcalFromNutrition,
} from './format'

describe('order history mapping', () => {
  it('localizes shop/item names and paid totals from API shape', () => {
    const raw = {
      content: [
        {
          shopId: 5,
          shopType: 'CAFE',
          shopName: { ko: 'kafé 5F', en: null },
          orderId: 1059669,
          orderNo: '00466',
          goodsOrderItems: [
            {
              id: 1,
              name: { ko: '혼합 아이스크림', en: '혼합 아이스크림' },
              goodsQty: 1,
              paidPrice: 2000,
              salesPrice: 2000,
              unitPrice: 2000,
              goodsOrderItemOptions: [
                {
                  optionName: { ko: '토핑' },
                  optionMenus: [{ name: { ko: '토핑 없음' }, optionPrice: 0 }],
                },
              ],
            },
          ],
          mealOrderItems: null,
          status: 'ORDER_COMPLETE',
          regAt: '2026-07-14T14:43:29.483891+09:00',
          totalPaidPrice: 2000,
          totalSalesPrice: 2000,
        },
      ],
    }
    const list = mapOrderHistory(raw)
    expect(list).toHaveLength(1)
    expect(list[0].shopName).toBe('kafé 5F')
    expect(list[0].orderNo).toBe('00466')
    expect(list[0].totalPaid).toBe(2000)
    expect(list[0].items[0].name).toBe('혼합 아이스크림')
    expect(list[0].items[0].options[0]).toContain('토핑 없음')
    expect(orderStatusLabel(list[0].status)).toBe('완료')
  })

  it('maps cafeteria mealOrderItems (mealName/courseName)', () => {
    const raw = {
      content: [
        {
          shopId: 7,
          shopType: 'CAFETERIA',
          shopName: { ko: '춘식도락(B1F)' },
          orderId: 1,
          orderNo: '00026',
          goodsOrderItems: null,
          mealOrderItems: [
            {
              courseName: { ko: '한식B' },
              operationTimeTitle: { ko: '중식' },
              mealName: { ko: '소고기미역국' },
              mealQty: 1,
              paidPrice: 8000,
              salesPrice: 8000,
              unitPrice: 8000,
            },
          ],
          status: 'ORDER_COMPLETE',
          regAt: '2026-07-14T11:00:00+09:00',
          totalSalesPrice: 8000,
          totalPaidPrice: null,
        },
      ],
    }
    const list = mapOrderHistory(raw)
    expect(list[0].items[0].name).toContain('소고기미역국')
    expect(list[0].items[0].name).toContain('한식B')
    expect(list[0].totalPaid).toBe(8000)
  })
})

describe('cafe recent/popular mapping', () => {
  it('maps thumbnail and displayId for re-order navigation', () => {
    const raw = {
      content: [
        {
          displayId: 210,
          goodsId: 293,
          name: { ko: '혼합 아이스크림' },
          goodsQty: 1,
          thumbnail: 'pre/goods/x.jpg',
          thumbnailYn: true,
          lastOrderAt: '2026-07-14T14:43:29+09:00',
          isSale: true,
          stockEmptyYn: false,
        },
      ],
    }
    const items = mapCafeQuickItems(raw)
    expect(items[0].displayId).toBe(210)
    expect(items[0].name).toBe('혼합 아이스크림')
    expect(items[0].thumbnailUrl).toBe(mediaUrl('pre/goods/x.jpg'))
    expect(items[0].soldOut).toBe(false)
  })
})

describe('dining menu images', () => {
  it('extracts meal image from fileItems and kcal from nutrition text', () => {
    const raw = {
      content: [
        {
          salesDate: '2026-07-15',
          mealOperationTimes: [
            {
              title: { ko: '중식' },
              startTime: '11:00:00',
              endTime: '14:00:00',
              courses: [
                {
                  name: { ko: '한식A' },
                  congestionType: 'SMOOTH',
                  soldOutYn: false,
                  origin: { ko: '쌀 (국내산)' },
                  pricePlans: [
                    { payMethodType: 'NORMAL', price: 10000 },
                    { payMethodType: 'IDCARD', price: 2000 },
                  ],
                  meals: [
                    {
                      name: { ko: '[초복특식]마늘보쌈' },
                      nutrition: {
                        ko: '탄수화물 : 120.6g / 열량 : 902Kcal',
                      },
                      information: { ko: '정보' },
                      soldOutYn: false,
                      fileItems: [
                        {
                          filePath: 'data/box/venus/kakao/7/IMG_9105.jpeg',
                          thumbnailYn: false,
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    }
    const periods = mapDiningMenu(raw)
    expect(periods[0].courses[0].price).toBe(8000)
    const meal = periods[0].courses[0].menus[0]
    expect(meal.name).toContain('마늘보쌈')
    expect(meal.calorie).toBe(902)
    expect(meal.imageUrl).toBe(
      `${ELIGA_CDN_BASE}data/box/venus/kakao/7/IMG_9105.jpeg`,
    )
    expect(parseKcalFromNutrition('열량 : 902Kcal')).toBe(902)
  })

  it('keeps path segments URL-safe while preserving parentheses per encodeURIComponent', () => {
    // encodeURIComponent does not escape ( ) per ECMAScript; spaces etc. still encoded
    expect(mediaUrl('data/box/venus/kakao/7/IMG_9126(1).jpeg')).toBe(
      `${ELIGA_CDN_BASE}data/box/venus/kakao/7/IMG_9126(1).jpeg`,
    )
    expect(mediaUrl('data/box/a b/c.jpeg')).toBe(
      `${ELIGA_CDN_BASE}data/box/a%20b/c.jpeg`,
    )
  })
})
