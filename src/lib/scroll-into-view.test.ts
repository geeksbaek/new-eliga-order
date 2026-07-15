/** @vitest-environment jsdom */
import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import {
  computeScrollDelta,
  predictedDiningGroupHeight,
  scrollBlockIntoView,
} from './scroll-into-view'

describe('predictedDiningGroupHeight', () => {
  it('sums head and body scroll heights', () => {
    const el = document.createElement('div')
    const head = document.createElement('div')
    head.className = 'dining-group-head'
    Object.defineProperty(head, 'offsetHeight', { value: 48 })
    const body = document.createElement('div')
    body.className = 'dining-group-body'
    Object.defineProperty(body, 'scrollHeight', { value: 200 })
    el.append(head, body)
    expect(predictedDiningGroupHeight(el)).toBe(48 + 200 + 2)
  })
})

describe('computeScrollDelta / scrollBlockIntoView', () => {
  const originalScrollBy = window.scrollBy

  beforeEach(() => {
    window.scrollBy = vi.fn()
    vi.spyOn(window, 'innerHeight', 'get').mockReturnValue(800)
  })

  afterEach(() => {
    window.scrollBy = originalScrollBy
    vi.restoreAllMocks()
  })

  function elAt(top: number, height = 20): HTMLElement {
    const el = document.createElement('div')
    el.getBoundingClientRect = () =>
      ({
        top,
        bottom: top + height,
        height,
        left: 0,
        right: 0,
        width: 0,
        x: 0,
        y: top,
        toJSON: () => ({}),
      }) as DOMRect
    return el
  }

  it('scrolls down when bottom is below the fold', () => {
    const el = elAt(500)
    const delta = computeScrollDelta(el, 400, {
      marginTop: 8,
      marginBottom: 12,
    })
    expect(delta).toBeGreaterThan(0)

    scrollBlockIntoView(el, {
      behavior: 'instant',
      predictedHeight: 400,
      marginTop: 8,
      marginBottom: 12,
    })
    expect(window.scrollBy).toHaveBeenCalled()
  })

  it('returns 0 when fully visible', () => {
    const el = elAt(100)
    expect(
      computeScrollDelta(el, 200, { marginTop: 8, marginBottom: 12 }),
    ).toBe(0)
  })

  it('pins header when taller than viewport', () => {
    const el = elAt(200)
    const delta = computeScrollDelta(el, 2000, {
      marginTop: 8,
      marginBottom: 12,
    })
    expect(delta).toBeCloseTo(192, 0)
  })
})
