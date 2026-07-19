import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  FAVORITES_CHANGED_EVENT,
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
  vi.restoreAllMocks()
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

  it('dispatches favorites-changed event on toggle', () => {
    const listeners = new Map<string, Set<EventListener>>()
    const win = {
      addEventListener(type: string, fn: EventListener) {
        const set = listeners.get(type) ?? new Set()
        set.add(fn)
        listeners.set(type, set)
      },
      removeEventListener(type: string, fn: EventListener) {
        listeners.get(type)?.delete(fn)
      },
      dispatchEvent(ev: Event) {
        for (const fn of listeners.get(ev.type) ?? []) fn(ev)
        return true
      },
    }
    vi.stubGlobal('window', win)
    vi.stubGlobal(
      'CustomEvent',
      class CustomEvent<T = unknown> extends Event {
        detail: T
        constructor(type: string, init?: CustomEventInit<T>) {
          super(type)
          this.detail = (init?.detail ?? undefined) as T
        }
      },
    )

    const spy = vi.fn()
    win.addEventListener(FAVORITES_CHANGED_EVENT, spy)
    toggleFavorite(10, 5)
    expect(spy).toHaveBeenCalledTimes(1)
    expect((spy.mock.calls[0][0] as CustomEvent).detail.count).toBe(1)
    toggleFavorite(10, 5)
    expect(spy).toHaveBeenCalledTimes(2)
    expect((spy.mock.calls[1][0] as CustomEvent).detail.count).toBe(0)
  })
})
