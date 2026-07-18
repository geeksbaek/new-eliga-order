import { describe, expect, it, vi } from 'vitest'
import { isStandaloneDisplay } from './display-mode'

function mockWin(opts: {
  standaloneMq?: boolean
  fullscreenMq?: boolean
  minimalMq?: boolean
  iosStandalone?: boolean
}) {
  const matchMedia = vi.fn((q: string) => ({
    matches:
      (q.includes('standalone') && Boolean(opts.standaloneMq)) ||
      (q.includes('fullscreen') && Boolean(opts.fullscreenMq)) ||
      (q.includes('minimal-ui') && Boolean(opts.minimalMq)),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  }))
  return {
    matchMedia,
    navigator: { standalone: opts.iosStandalone },
  } as unknown as Window & {
    navigator: Navigator & { standalone?: boolean }
  }
}

describe('isStandaloneDisplay', () => {
  it('is false in normal browser tab', () => {
    expect(isStandaloneDisplay(mockWin({}))).toBe(false)
  })

  it('is true for display-mode: standalone', () => {
    expect(isStandaloneDisplay(mockWin({ standaloneMq: true }))).toBe(true)
  })

  it('is true for iOS navigator.standalone', () => {
    expect(isStandaloneDisplay(mockWin({ iosStandalone: true }))).toBe(true)
  })

  it('is true for fullscreen / minimal-ui', () => {
    expect(isStandaloneDisplay(mockWin({ fullscreenMq: true }))).toBe(true)
    expect(isStandaloneDisplay(mockWin({ minimalMq: true }))).toBe(true)
  })
})
