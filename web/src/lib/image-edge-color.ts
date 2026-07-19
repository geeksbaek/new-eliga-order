/**
 * Sample a letterbox-friendly background color from image edge pixels.
 * CDN has no CORS, so sampling goes through same-origin /api/cdn.
 */
import { ELIGA_CDN_BASE } from './format'

const FALLBACK = '#ffffff'

/** Build same-origin proxy URL for an Eliga CDN image (for canvas sampling). */
export function eligaCdnProxyUrl(src: string): string | null {
  const url = src.trim()
  if (!url) return null
  try {
    const absolute = url.startsWith(ELIGA_CDN_BASE)
      ? url
      : url.startsWith('http')
        ? url
        : null
    if (!absolute) return null
    const u = new URL(absolute)
    if (u.hostname !== 'kr.object.ncloudstorage.com') return null
    if (!u.pathname.startsWith('/eliga-order/')) return null
    // pathname is decoded; query-encode once for /api/cdn
    const path = u.pathname.slice('/eliga-order/'.length).replace(/^\/+/, '')
    if (!path || path.includes('..')) return null
    return `/api/cdn?path=${encodeURIComponent(path)}`
  } catch {
    return null
  }
}

/** Average opaque pixels along the border of an ImageData buffer. */
export function averageEdgeRgb(
  data: Uint8ClampedArray | Uint8Array,
  width: number,
  height: number,
): { r: number; g: number; b: number } | null {
  if (width < 1 || height < 1 || data.length < width * height * 4) return null
  let r = 0
  let g = 0
  let b = 0
  let n = 0

  const add = (x: number, y: number) => {
    const i = (y * width + x) * 4
    const a = data[i + 3] ?? 0
    if (a < 24) return
    r += data[i] ?? 0
    g += data[i + 1] ?? 0
    b += data[i + 2] ?? 0
    n += 1
  }

  for (let x = 0; x < width; x++) {
    add(x, 0)
    if (height > 1) add(x, height - 1)
  }
  for (let y = 1; y < height - 1; y++) {
    add(0, y)
    if (width > 1) add(width - 1, y)
  }

  if (n === 0) return null
  return {
    r: Math.round(r / n),
    g: Math.round(g / n),
    b: Math.round(b / n),
  }
}

export function rgbToCss(c: { r: number; g: number; b: number }): string {
  return `rgb(${c.r}, ${c.g}, ${c.b})`
}

/**
 * Load image (via CDN proxy when needed) and return edge-average CSS color.
 * Falls back to white on failure / missing CORS path.
 */
export async function sampleImageEdgeColor(
  src: string | null | undefined,
): Promise<string> {
  if (!src?.trim()) return FALLBACK
  const sampleSrc = eligaCdnProxyUrl(src) ?? src

  return new Promise((resolve) => {
    const img = new Image()
    // Same-origin proxy does not need CORS flag; keep anonymous for safety
    img.crossOrigin = 'anonymous'
    img.decoding = 'async'

    const finish = (color: string) => resolve(color)

    img.onload = () => {
      try {
        const nw = img.naturalWidth || img.width
        const nh = img.naturalHeight || img.height
        if (!nw || !nh) {
          finish(FALLBACK)
          return
        }
        const maxSide = 48
        const scale = Math.min(1, maxSide / Math.max(nw, nh))
        const w = Math.max(1, Math.round(nw * scale))
        const h = Math.max(1, Math.round(nh * scale))
        const canvas = document.createElement('canvas')
        canvas.width = w
        canvas.height = h
        const ctx = canvas.getContext('2d', { willReadFrequently: true })
        if (!ctx) {
          finish(FALLBACK)
          return
        }
        ctx.drawImage(img, 0, 0, w, h)
        const { data } = ctx.getImageData(0, 0, w, h)
        const avg = averageEdgeRgb(data, w, h)
        finish(avg ? rgbToCss(avg) : FALLBACK)
      } catch {
        finish(FALLBACK)
      }
    }
    img.onerror = () => finish(FALLBACK)
    img.src = sampleSrc
  })
}
