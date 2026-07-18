import type { VercelRequest, VercelResponse } from '@vercel/node'
import dns from 'node:dns'

try {
  dns.setDefaultResultOrder('ipv4first')
} catch {
  /* node < 17 */
}

/** Near Korea; CDN is NCloud KR. */
export const config = {
  regions: ['icn1'],
  maxDuration: 15,
}

const CDN_ORIGIN = 'https://kr.object.ncloudstorage.com/eliga-order/'
const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
const MAX_BYTES = 5 * 1024 * 1024

/**
 * Same-origin image proxy for canvas color sampling (CDN has no CORS).
 *
 * GET /api/cdn?path=pre/goods/x.jpg
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader('X-Content-Type-Options', 'nosniff')
  res.setHeader('Referrer-Policy', 'no-referrer')

  if (req.method && req.method !== 'GET') {
    res.status(405).json({ error: 'method_not_allowed' })
    return
  }

  const raw = String(req.query.path || '')
  let decoded: string
  try {
    decoded = decodeURIComponent(raw).replace(/^\/+/, '')
  } catch {
    res.status(400).json({ error: 'bad_path' })
    return
  }
  if (
    !decoded ||
    decoded.includes('..') ||
    decoded.includes('\\') ||
    decoded.includes('://') ||
    decoded.startsWith('//') ||
    decoded.startsWith('http') ||
    /[\u0000-\u001f]/.test(decoded)
  ) {
    res.status(400).json({ error: 'bad_path' })
    return
  }

  const encoded = decoded
    .split('/')
    .filter(Boolean)
    .map((s) => encodeURIComponent(s))
    .join('/')
  const target = `${CDN_ORIGIN}${encoded}`

  try {
    const targetUrl = new URL(target)
    if (
      targetUrl.hostname !== 'kr.object.ncloudstorage.com' ||
      targetUrl.protocol !== 'https:' ||
      !targetUrl.pathname.startsWith('/eliga-order/')
    ) {
      res.status(400).json({ error: 'host_not_allowed' })
      return
    }

    const up = await fetch(targetUrl.toString(), {
      headers: {
        Accept: 'image/*,*/*',
        'User-Agent': UA,
      },
    })
    if (!up.ok) {
      res.status(up.status).json({ error: 'upstream_failed' })
      return
    }
    const buf = Buffer.from(await up.arrayBuffer())
    const ct = (up.headers.get('content-type') || 'image/jpeg')
      .split(';')[0]
      .trim()
      .toLowerCase()
    if (!ct.startsWith('image/')) {
      res.status(415).json({ error: 'unsupported_media_type' })
      return
    }
    if (buf.byteLength > MAX_BYTES) {
      res.status(413).json({ error: 'payload_too_large' })
      return
    }
    res.setHeader('Content-Type', ct)
    res.setHeader(
      'Cache-Control',
      'public, max-age=86400, stale-while-revalidate=604800',
    )
    res.status(200).send(buf)
  } catch {
    res.status(502).json({
      error: 'proxy_upstream_failed',
      message: 'upstream fetch failed',
    })
  }
}
