import type { VercelRequest, VercelResponse } from '@vercel/node'

const WEBAPP = 'https://webapp.eligaorder.com'
const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'

const UPSTREAMS: Record<string, string> = {
  base: 'https://base.eligaorder.com',
  svc: 'https://svc.eligaorder.com',
}

function rewriteCookies(setCookie: string[]): string[] {
  return setCookie.map((c) =>
    c
      .replace(/;\s*Domain=[^;]*/gi, '')
      .replace(/;\s*SameSite=[^;]*/gi, '')
      .concat('; SameSite=Lax; Path=/; Secure'),
  )
}

/**
 * Single proxy endpoint (avoids Vercel multi-segment catch-all issues).
 *
 * GET  /api/proxy?to=base&path=space&brandCode=kakao
 * POST /api/proxy?to=svc&path=venus/customer/sign-in
 *      body: {...}
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
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

  const headers: Record<string, string> = {
    Accept: String(req.headers.accept || 'application/json'),
    'User-Agent': UA,
    Origin: WEBAPP,
    Referer: `${WEBAPP}/`,
  }
  if (req.headers['content-type']) {
    headers['Content-Type'] = String(req.headers['content-type'])
  }
  if (req.headers.cookie) headers.Cookie = String(req.headers.cookie)
  if (req.headers.authorization) {
    headers.Authorization = String(req.headers.authorization)
  }

  let body: string | undefined
  if (req.method && !['GET', 'HEAD'].includes(req.method)) {
    if (typeof req.body === 'string') body = req.body
    else if (req.body != null && req.body !== '') body = JSON.stringify(req.body)
    if (body != null) headers['Content-Length'] = String(Buffer.byteLength(body))
  }

  let upstreamRes: Response
  try {
    upstreamRes = await fetch(target, {
      method: req.method || 'GET',
      headers,
      body,
    })
  } catch (err) {
    res.status(502).json({
      error: 'proxy_upstream_failed',
      target,
      message: err instanceof Error ? err.message : String(err),
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
    (req.method || 'GET').toUpperCase() === 'POST' &&
    upstreamRes.status === 200

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
      k === 'set-cookie'
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
  res.setHeader('x-eliga-proxy-target', target)
  res.send(text)
}
