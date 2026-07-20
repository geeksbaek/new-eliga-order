#!/usr/bin/env node
/**
 * Static SPA + Eliga API reverse proxy.
 * Makes AccessToken cookies first-party and injects JWT into sign-in JSON
 * so the browser client can authenticate (mirrors eliga-api.sh cookie flow).
 *
 *   npm run build && npm start
 *   open http://127.0.0.1:8787/
 */
import http from 'node:http'
import https from 'node:https'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { URL } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const DIST = path.join(__dirname, 'dist')
const PORT = Number(process.env.PORT || 3456)
const HOST = process.env.HOST || '127.0.0.1'

const BASE_UPSTREAM = 'https://base.eligaorder.com'
const SVC_UPSTREAM = 'https://svc.eligaorder.com'
const WEBAPP_ORIGIN = 'https://webapp.eligaorder.com'
const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.ico': 'image/x-icon',
  '.json': 'application/json',
  '.woff2': 'font/woff2',
  '.map': 'application/json',
}

const CDN_ORIGIN = 'https://kr.object.ncloudstorage.com/eliga-order/'

function isSafeProxyPath(path) {
  if (!path) return false
  if (path.includes('..') || path.includes('\\')) return false
  if (path.includes('://') || path.startsWith('//')) return false
  if (/[\u0000-\u001f]/.test(path)) return false
  if (!/^[a-zA-Z0-9._\-/:%]+$/.test(path)) return false
  return true
}

function rewriteLocalCookies(setCookie) {
  const list = Array.isArray(setCookie) ? setCookie : setCookie ? [setCookie] : []
  return list.map((c) =>
    c
      .replace(/;\s*Domain=[^;]*/gi, '')
      .replace(/;\s*SameSite=[^;]*/gi, '')
      .replace(/;\s*Secure/gi, '')
      .replace(/;\s*HttpOnly/gi, '')
      .replace(/;\s*Path=[^;]*/gi, '')
      .concat('; Path=/; HttpOnly; SameSite=Lax'),
  )
}

function proxyCdn(req, res) {
  const u = new URL(req.url || '/', `http://${req.headers.host}`)
  const pathRaw = (u.searchParams.get('path') || '').replace(/^\/+/, '')
  if (
    !pathRaw ||
    pathRaw.includes('..') ||
    pathRaw.includes('://') ||
    pathRaw.startsWith('//')
  ) {
    res.writeHead(400, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ error: 'bad_path' }))
    return
  }
  let decoded
  try {
    decoded = decodeURIComponent(pathRaw)
  } catch {
    res.writeHead(400, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ error: 'bad_path' }))
    return
  }
  const encoded = decoded
    .split('/')
    .filter(Boolean)
    .map((s) => encodeURIComponent(s))
    .join('/')
  const target = new URL(`${CDN_ORIGIN}${encoded}`)
  if (
    target.hostname !== 'kr.object.ncloudstorage.com' ||
    target.protocol !== 'https:'
  ) {
    res.writeHead(400, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ error: 'host_not_allowed' }))
    return
  }
  const lib = https
  const up = lib.request(
    target,
    {
      method: 'GET',
      headers: { accept: 'image/*,*/*', 'user-agent': UA },
    },
    (upRes) => {
      const ct = String(upRes.headers['content-type'] || 'image/jpeg')
        .split(';')[0]
        .trim()
        .toLowerCase()
      if (!ct.startsWith('image/')) {
        res.writeHead(415, { 'content-type': 'application/json' })
        res.end(JSON.stringify({ error: 'unsupported_media_type' }))
        upRes.resume()
        return
      }
      const outHeaders = {
        'content-type': ct,
        'cache-control': 'public, max-age=86400',
        'x-content-type-options': 'nosniff',
      }
      res.writeHead(upRes.statusCode || 502, outHeaders)
      upRes.pipe(res)
    },
  )
  up.on('error', () => {
    res.writeHead(502, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ error: 'upstream_failed' }))
  })
  up.end()
}

function proxyQuery(req, res) {
  const u = new URL(req.url || '/', `http://${req.headers.host}`)
  const to = u.searchParams.get('to')
  const path = (u.searchParams.get('path') || '').replace(/^\/+/, '')
  const upstream =
    to === 'base' ? BASE_UPSTREAM : to === 'svc' ? SVC_UPSTREAM : null
  if (!upstream || !path) {
    res.writeHead(400, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ error: 'query.to and query.path required' }))
    return
  }
  if (!isSafeProxyPath(path)) {
    res.writeHead(400, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ error: 'invalid_path' }))
    return
  }
  u.searchParams.delete('to')
  u.searchParams.delete('path')
  const qs = u.searchParams.toString()
  const targetUrl = `${upstream}/${path}${qs ? `?${qs}` : ''}`
  let target
  try {
    target = new URL(targetUrl)
  } catch {
    res.writeHead(400, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ error: 'invalid_target' }))
    return
  }
  if (target.hostname !== new URL(upstream).hostname || target.protocol !== 'https:') {
    res.writeHead(400, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ error: 'host_not_allowed' }))
    return
  }

  const headers = {
    accept: req.headers.accept || 'application/json',
    'user-agent': UA,
    origin: WEBAPP_ORIGIN,
    referer: `${WEBAPP_ORIGIN}/`,
  }
  const ct = req.headers['content-type']
  if (ct && String(ct).toLowerCase().includes('application/json')) {
    headers['content-type'] = ct
  }
  if (req.headers.authorization && /^Bearer\s+\S+/i.test(String(req.headers.authorization))) {
    headers.authorization = req.headers.authorization
  }
  if (req.headers.cookie) headers.cookie = req.headers.cookie

  const chunks = []
  let size = 0
  const MAX = 512 * 1024
  req.on('data', (c) => {
    size += c.length
    if (size > MAX) {
      res.writeHead(413, { 'content-type': 'application/json' })
      res.end(JSON.stringify({ error: 'payload_too_large' }))
      req.destroy()
      return
    }
    chunks.push(c)
  })
  req.on('end', () => {
    const body = Buffer.concat(chunks)
    const opts = {
      method: req.method,
      headers: { ...headers, 'content-length': body.length },
    }
    const lib = target.protocol === 'https:' ? https : http
    const up = lib.request(target, opts, (upRes) => {
      const setCookies = upRes.headers['set-cookie']
      const outHeaders = { ...upRes.headers }
      if (setCookies) {
        outHeaders['set-cookie'] = rewriteLocalCookies(setCookies)
      }
      delete outHeaders['access-control-allow-origin']
      delete outHeaders['access-control-allow-credentials']
      outHeaders['x-content-type-options'] = 'nosniff'
      outHeaders['cache-control'] = 'no-store'

      const isSignIn =
        target.pathname.endsWith('/customer/sign-in') && req.method === 'POST'

      if (!isSignIn) {
        res.writeHead(upRes.statusCode || 502, outHeaders)
        upRes.pipe(res)
        return
      }

      const bufs = []
      upRes.on('data', (d) => bufs.push(d))
      upRes.on('end', () => {
        let raw = Buffer.concat(bufs).toString('utf8')
        let accessFromCookie = null
        const list = Array.isArray(setCookies) ? setCookies : setCookies ? [setCookies] : []
        for (const c of list) {
          const m = /^AccessToken=([^;]+)/i.exec(c)
          if (m) accessFromCookie = decodeURIComponent(m[1])
        }
        if (accessFromCookie && upRes.statusCode === 200) {
          try {
            const json = raw ? JSON.parse(raw) : {}
            const content =
              json && typeof json.content === 'object' && json.content
                ? { ...json.content }
                : {}
            if (!content.accessToken) {
              content.accessToken = accessFromCookie
              content.tokenType = content.tokenType || 'Bearer'
              json.content = content
              raw = JSON.stringify(json)
              outHeaders['content-type'] = 'application/json; charset=utf-8'
              outHeaders['content-length'] = Buffer.byteLength(raw)
            }
          } catch {
            /* keep */
          }
        }
        res.writeHead(upRes.statusCode || 502, outHeaders)
        res.end(raw)
      })
    })
    up.on('error', () => {
      res.writeHead(502, { 'content-type': 'application/json' })
      res.end(JSON.stringify({ error: 'upstream_failed' }))
    })
    if (body.length) up.write(body)
    up.end()
  })
}

function sendFile(res, filePath) {
  const ext = path.extname(filePath)
  const type = MIME[ext] || 'application/octet-stream'
  res.writeHead(200, { 'content-type': type })
  fs.createReadStream(filePath).pipe(res)
}

function tryStatic(req, res) {
  let urlPath = decodeURIComponent((req.url || '/').split('?')[0])
  if (urlPath === '/') urlPath = '/index.html'

  // Prefer exact file, then directory index, then SPA fallback
  const candidates = [
    path.join(DIST, urlPath),
    path.join(DIST, urlPath, 'index.html'),
    path.join(DIST, 'index.html'),
  ]
  for (const file of candidates) {
    if (file.startsWith(DIST) && fs.existsSync(file) && fs.statSync(file).isFile()) {
      sendFile(res, file)
      return true
    }
  }
  return false
}

const server = http.createServer((req, res) => {
  const url = req.url || '/'
  if (url.startsWith('/api/cdn')) {
    return proxyCdn(req, res)
  }
  if (url.startsWith('/api/proxy')) {
    return proxyQuery(req, res)
  }
  if (!tryStatic(req, res)) {
    res.writeHead(404, { 'content-type': 'text/plain' })
    res.end('Not found')
  }
})

if (!fs.existsSync(path.join(DIST, 'index.html'))) {
  console.error('dist/index.html missing. Run: npm run build')
  process.exit(1)
}

server.listen(PORT, HOST, () => {
  console.log(`new 엘리가오더  http://${HOST}:${PORT}/`)
  console.log('API proxy: /api/proxy?to=base|svc&path=...')
})
