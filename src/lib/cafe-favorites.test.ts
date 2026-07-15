import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import {
  isFavorite,
  loadFavorites,
  toggleFavorite,
} from './cafe-favorites'

const KEY = 'eliga.cafe.favorites'
const mem = new Map<string, string>()

beforeEach(() => {
  mem.clear()
  Object.defineProperty(globalThis, 'localStorage', {
    configurable: true,
    value: {
      getItem: (k: string) => mem.get(k) ?? null,
      setItem: (k: string, v: string) => {
        mem.set(k, String(v))
      },
      removeItem: (k: string) => {
        mem.delete(k)
      },
      clear: () => mem.clear(),
    },
  })
})

afterEach(() => {
  mem.clear()
})

describe('cafe-favorites multi-shop', () => {
  it('starts empty', () => {
    expect(loadFavorites()).toEqual([])
  })

  it('toggles with shopId', () => {
    expect(toggleFavorite(10, 5)).toEqual([{ displayId: 10, shopId: 5 }])
    expect(toggleFavorite(20, 4)).toEqual([
      { displayId: 10, shopId: 5 },
      { displayId: 20, shopId: 4 },
    ])
    expect(toggleFavorite(10, 5)).toEqual([{ displayId: 20, shopId: 4 }])
    expect(isFavorite(20, 4)).toBe(true)
    expect(isFavorite(10, 5)).toBe(false)
  })

  it('migrates legacy bare displayIds', () => {
    mem.set(KEY, '[7,8]')
    expect(loadFavorites()).toEqual([
      { displayId: 7, shopId: 0 },
      { displayId: 8, shopId: 0 },
    ])
    expect(isFavorite(7, 5)).toBe(true) // shop 0 matches any shop
  })

  it('ignores invalid ids', () => {
    expect(toggleFavorite(0, 5)).toEqual([])
    expect(toggleFavorite(1, 0)).toEqual([])
  })
})
