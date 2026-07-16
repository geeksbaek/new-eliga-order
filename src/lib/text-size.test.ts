/**
 * @vitest-environment jsdom
 */
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import {
  TEXT_SIZE_CLASS,
  applyTextSize,
  loadTextSize,
  saveTextSize,
} from './text-size'

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
  document.documentElement.classList.remove(TEXT_SIZE_CLASS)
})

afterEach(() => {
  document.documentElement.classList.remove(TEXT_SIZE_CLASS)
})

describe('text-size', () => {
  it('defaults to normal', () => {
    expect(loadTextSize()).toBe('normal')
  })

  it('persists large and toggles html class', () => {
    saveTextSize('large')
    expect(loadTextSize()).toBe('large')
    expect(document.documentElement.classList.contains(TEXT_SIZE_CLASS)).toBe(
      true,
    )
    saveTextSize('normal')
    expect(loadTextSize()).toBe('normal')
    expect(document.documentElement.classList.contains(TEXT_SIZE_CLASS)).toBe(
      false,
    )
  })

  it('applyTextSize sets class without save', () => {
    applyTextSize('large')
    expect(document.documentElement.classList.contains(TEXT_SIZE_CLASS)).toBe(
      true,
    )
  })
})
