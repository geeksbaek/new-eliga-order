import type { VercelRequest, VercelResponse } from '@vercel/node'

const UPSTREAM = 'https://svc.eligaorder.com'
const WEBAPP = 'https://webapp.eligaorder.com'
const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'

function rewriteCookies(setCookie: string[]): string[] {
  return setCookie.map((c) =>
    c
      .replace(/;\s*Domain=[^;]*/gi, '')
      .replace(/;\s*SameSite=[^;]*/gi, '')
      .concat('; SameSite=Lax; Path=/; Secure'),
  )
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const parts = req.query.path
  const pathSegs = Array.isArray(parts) ? parts : parts ? [parts] : []
  const qs = req.url?.includes('?') ? req.url.slice(req.url.indexOf('?')) : ''
  const targetPath = pathSegs.map(encodeURIComponent).join('/')
  const target = `${UPSTREAM}/${targetPath}${qs}`

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

  const init: RequestInit = {
    method: req.method || 'GET',
    headers,
  }
  if (req.method && !['GET', 'HEAD'].includes(req.method)) {
    init.body =
      typeof req.body === 'string' ? req.body : JSON.stringify(req.body ?? {})
  }

  const upstream = await fetch(target, init)
  let bodyText = await upstream.text()

  const cookies =
    typeof upstream.headers.getSetCookie === 'function'
      ? upstream.headers.getSetCookie()
      : []

  // Inject AccessToken into sign-in JSON (official API uses HttpOnly cookie only)
  const isSignIn =
    targetPath.endsWith('customer/sign-in') &&
    (req.method || 'GET').toUpperCase() === 'POST' &&
    upstream.status === 200

  if (isSignIn) {
    let accessFromCookie: string | null = null
    for (const c of cookies) {
      const m = /^AccessToken=([^;]+)/i.exec(c)
      if (m) accessFromCookie = decodeURIComponent(m[1])
    }
    if (accessFromCookie) {
      try {
        const json = bodyText ? JSON.parse(bodyText) : {}
        const content =
          json && typeof json.content === 'object' && json.content
            ? { ...json.content }
            : {}
        if (!content.accessToken) {
          content.accessToken = accessFromCookie
          content.tokenType = content.tokenType || 'Bearer'
          json.content = content
          bodyText = JSON.stringify(json)
        }
      } catch {
        /* keep body */
      }
    }
  }

  res.status(upstream.status)
  upstream.headers.forEach((value, key) => {
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
  if (isSignIn) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8')
  }
  res.send(bodyText)
}
