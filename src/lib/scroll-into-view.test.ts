/** @vitest-environment jsdom */
import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import {
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

describe('scrollBlockIntoView', () => {
  const originalScrollBy = window.scrollBy

  beforeEach(() => {
    window.scrollBy = vi.fn()
    // Minimal viewport chrome: no tab/dock → use innerHeight
    vi.spyOn(window, 'innerHeight', 'get').mockReturnValue(800)
  })

  afterEach(() => {
    window.scrollBy = originalScrollBy
    vi.restoreAllMocks()
  })

  it('scrolls down when predicted bottom is below the fold', () => {
    const el = document.createElement('div')
    el.getBoundingClientRect = () =>
      ({
        top: 500,
        bottom: 520,
        height: 20,
        left: 0,
        right: 0,
        width: 0,
        x: 0,
        y: 500,
        toJSON: () => ({}),
      }) as DOMRect

    scrollBlockIntoView(el, {
      behavior: 'instant',
      margin: 10,
      predictedHeight: 400, // bottom = 900 > 790
    })

    expect(window.scrollBy).toHaveBeenCalledWith(
      expect.objectContaining({ top: expect.any(Number) }),
    )
    const arg = vi.mocked(window.scrollBy).mock.calls[0][0] as ScrollToOptions
    expect(arg.top).toBeGreaterThan(0)
  })

  it('does not scroll when fully visible', () => {
    const el = document.createElement('div')
    el.getBoundingClientRect = () =>
      ({
        top: 100,
        bottom: 300,
        height: 200,
        left: 0,
        right: 0,
        width: 0,
        x: 0,
        y: 100,
        toJSON: () => ({}),
      }) as DOMRect

    scrollBlockIntoView(el, {
      behavior: 'instant',
      margin: 10,
      predictedHeight: 200,
    })

    expect(window.scrollBy).not.toHaveBeenCalled()
  })
})
