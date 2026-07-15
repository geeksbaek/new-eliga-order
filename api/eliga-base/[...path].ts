import type { VercelRequest, VercelResponse } from '@vercel/node'

const UPSTREAM = 'https://base.eligaorder.com'
const WEBAPP = 'https://webapp.eligaorder.com'
const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const parts = req.query.path
  const pathSegs = Array.isArray(parts) ? parts : parts ? [parts] : []
  const qs = req.url?.includes('?') ? req.url.slice(req.url.indexOf('?')) : ''
  const target = `${UPSTREAM}/${pathSegs.map(encodeURIComponent).join('/')}${qs}`

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
  const buf = Buffer.from(await upstream.arrayBuffer())

  res.status(upstream.status)
  upstream.headers.forEach((value, key) => {
    const k = key.toLowerCase()
    if (k === 'transfer-encoding' || k === 'content-encoding') return
    if (k === 'set-cookie') return
    res.setHeader(key, value)
  })

  const cookies = typeof upstream.headers.getSetCookie === 'function'
    ? upstream.headers.getSetCookie()
    : []
  if (cookies.length) {
    res.setHeader(
      'Set-Cookie',
      cookies.map((c) =>
        c
          .replace(/;\s*Domain=[^;]*/gi, '')
          .replace(/;\s*SameSite=[^;]*/gi, '')
          .concat('; SameSite=Lax; Path=/; Secure'),
      ),
    )
  }

  res.send(buf)
}
