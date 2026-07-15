import type { VercelRequest, VercelResponse } from '@vercel/node'
import dns from 'node:dns'

// Prefer IPv4 — some upstreams fail on IPv6-first serverless runtimes
try {
  dns.setDefaultResultOrder('ipv4first')
} catch {
  /* node < 17 */
}

/** Run the API proxy near Korea; US regions often cannot reach Eliga. */
export const config = {
  regions: ['icn1'],
  maxDuration: 30,
}

const WEBAPP = 'https://webapp.eligaorder.com'
const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'

const UPSTREAMS: Record<string, string> = {
  base: 'https://base.eligaorder.com',
  svc: 'https://svc.eligaorder.com',
}

const ALLOWED_METHODS = new Set([
  'GET',
  'HEAD',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'OPTIONS',
])

/** Max JSON body we will forward (login/order payloads are small). */
const MAX_BODY_BYTES = 512 * 1024

function isSafeProxyPath(path: string): boolean {
  if (!path) return false
  if (path.includes('..') || path.includes('\\')) return false
  if (path.includes('://') || path.startsWith('//')) return false
  if (/[\u0000-\u001f]/.test(path)) return false
  // Keep path as relative API path segments only
  if (!/^[a-zA-Z0-9._\-/:%]+$/.test(path)) return false
  return true
}

function rewriteCookies(setCookie: string[]): string[] {
  return setCookie.map((c) => {
    let out = c
      .replace(/;\s*Domain=[^;]*/gi, '')
      .replace(/;\s*SameSite=[^;]*/gi, '')
      .replace(/;\s*Secure/gi, '')
      .replace(/;\s*HttpOnly/gi, '')
      .replace(/;\s*Path=[^;]*/gi, '')
    // Prefer first-party secure cookies; JS still gets JWT via body on sign-in
    out += '; Path=/; Secure; HttpOnly; SameSite=Lax'
    return out
  })
}

function setSecurityHeaders(res: VercelResponse) {
  res.setHeader('X-Content-Type-Options', 'nosniff')
  res.setHeader('Referrer-Policy', 'no-referrer')
  res.setHeader('Cache-Control', 'no-store')
}

/**
 * Single proxy endpoint (avoids Vercel multi-segment catch-all issues).
 *
 * GET  /api/proxy?to=base&path=space&brandCode=kakao
 * POST /api/proxy?to=svc&path=venus/customer/sign-in
 *      body: {...}
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  setSecurityHeaders(res)

  const method = (req.method || 'GET').toUpperCase()
  if (!ALLOWED_METHODS.has(method)) {
    res.status(405).json({ error: 'method_not_allowed' })
    return
  }
  if (method === 'OPTIONS') {
    res.status(204).end()
    return
  }

  const to = String(req.query.to || '')
  const upstream = UPSTREAMS[to]
  if (!upstream) {
    res.status(400).json({
      error: 'invalid_to',
      message: 'query.to must be "base" or "svc"',
    })
    return
  }

  let path = String(req.query.path || '')
  path = path.replace(/^\/+/, '')
  if (!path && to === 'base') {
    res.status(400).json({ error: 'missing_path' })
    return
  }
  if (path && !isSafeProxyPath(path)) {
    res.status(400).json({ error: 'invalid_path' })
    return
  }

  const sp = new URLSearchParams()
  for (const [k, v] of Object.entries(req.query)) {
    if (k === 'to' || k === 'path') continue
    if (Array.isArray(v)) {
      for (const item of v) sp.append(k, String(item))
    } else if (v != null) {
      sp.set(k, String(v))
    }
  }
  const qs = sp.toString()
  const target = `${upstream}/${path}${qs ? `?${qs}` : ''}`

  let targetUrl: URL
  try {
    targetUrl = new URL(target)
  } catch {
    res.status(400).json({ error: 'invalid_target' })
    return
  }
  const allowedHost = new URL(upstream).hostname
  if (targetUrl.hostname !== allowedHost || targetUrl.protocol !== 'https:') {
    res.status(400).json({ error: 'host_not_allowed' })
    return
  }

  const headers: Record<string, string> = {
    Accept: String(req.headers.accept || 'application/json'),
    'User-Agent': UA,
    Origin: WEBAPP,
    Referer: `${WEBAPP}/`,
  }
  // Only forward JSON content-type (avoid multipart abuse via this proxy)
  const ct = req.headers['content-type']
  if (ct && String(ct).toLowerCase().includes('application/json')) {
    headers['Content-Type'] = String(ct)
  }
  if (req.headers.cookie) headers.Cookie = String(req.headers.cookie)
  // Only forward Bearer tokens (reject weird schemes)
  const auth = req.headers.authorization
  if (auth && /^Bearer\s+\S+/i.test(String(auth))) {
    headers.Authorization = String(auth)
  }

  let body: string | undefined
  if (!['GET', 'HEAD'].includes(method)) {
    if (typeof req.body === 'string') body = req.body
    else if (req.body != null && req.body !== '') body = JSON.stringify(req.body)
    if (body != null) {
      if (Buffer.byteLength(body) > MAX_BODY_BYTES) {
        res.status(413).json({ error: 'payload_too_large' })
        return
      }
      headers['Content-Length'] = String(Buffer.byteLength(body))
    }
  }

  let upstreamRes: Response
  try {
    upstreamRes = await fetch(targetUrl.toString(), {
      method,
      headers,
      body,
    })
  } catch {
    res.status(502).json({
      error: 'proxy_upstream_failed',
      message: 'upstream fetch failed',
    })
    return
  }

  let text = await upstreamRes.text()
  const cookies =
    typeof upstreamRes.headers.getSetCookie === 'function'
      ? upstreamRes.headers.getSetCookie()
      : []

  const isSignIn =
    path.endsWith('customer/sign-in') &&
    method === 'POST' &&
    upstreamRes.status === 200

  // SPA needs JWT in JSON; upstream sometimes only sets HttpOnly AccessToken cookie.
  // Inject into body once — does not weaken cookie flags on Set-Cookie rewrite.
  if (isSignIn) {
    let accessFromCookie: string | null = null
    for (const c of cookies) {
      const m = /^AccessToken=([^;]+)/i.exec(c)
      if (m) accessFromCookie = decodeURIComponent(m[1])
    }
    if (accessFromCookie) {
      try {
        const json = text ? JSON.parse(text) : {}
        const content =
          json && typeof json.content === 'object' && json.content
            ? { ...json.content }
            : {}
        if (!content.accessToken) {
          content.accessToken = accessFromCookie
          content.tokenType = content.tokenType || 'Bearer'
          json.content = content
          text = JSON.stringify(json)
        }
      } catch {
        /* keep */
      }
    }
  }

  res.status(upstreamRes.status)
  upstreamRes.headers.forEach((value, key) => {
    const k = key.toLowerCase()
    if (
      k === 'transfer-encoding' ||
      k === 'content-encoding' ||
      k === 'content-length' ||
      k === 'set-cookie' ||
      k === 'access-control-allow-origin' ||
      k === 'access-control-allow-credentials'
    ) {
      return
    }
    res.setHeader(key, value)
  })
  if (cookies.length) {
    res.setHeader('Set-Cookie', rewriteCookies(cookies))
  }
  if (isSignIn || text.startsWith('{') || text.startsWith('[')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8')
  }
  res.send(text)
}
