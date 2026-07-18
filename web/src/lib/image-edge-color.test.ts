import { describe, expect, it } from 'vitest'
import {
  averageEdgeRgb,
  eligaCdnProxyUrl,
  rgbToCss,
} from './image-edge-color'
import { ELIGA_CDN_BASE } from './format'

describe('image-edge-color', () => {
  it('builds same-origin proxy for eliga CDN urls', () => {
    const src = `${ELIGA_CDN_BASE}pre/goods/x.jpg`
    expect(eligaCdnProxyUrl(src)).toBe(
      `/api/cdn?path=${encodeURIComponent('pre/goods/x.jpg')}`,
    )
  })

  it('rejects non-cdn urls', () => {
    expect(eligaCdnProxyUrl('https://example.com/a.jpg')).toBeNull()
  })

  it('averages opaque edge pixels', () => {
    // 3x3: center red, edges all white
    const w = 3
    const h = 3
    const data = new Uint8ClampedArray(w * h * 4)
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const i = (y * w + x) * 4
        const edge = x === 0 || y === 0 || x === w - 1 || y === h - 1
        data[i] = edge ? 255 : 200
        data[i + 1] = edge ? 255 : 0
        data[i + 2] = edge ? 255 : 0
        data[i + 3] = 255
      }
    }
    expect(averageEdgeRgb(data, w, h)).toEqual({ r: 255, g: 255, b: 255 })
    expect(rgbToCss({ r: 10, g: 20, b: 30 })).toBe('rgb(10, 20, 30)')
  })
})
