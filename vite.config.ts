/// <reference types="vitest/config" />
import { copyFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'

function spaRouteShells(): Plugin {
  const routeDirs = [
    'login',
    'cart',
    'orders',
    'order/confirm',
    'settings',
    'dining/7',
    'cafe/3',
    'cafe/3/menu',
    'cafe/4',
    'cafe/4/menu',
    'cafe/5',
    'cafe/5/menu',
    'cafe/8',
    'cafe/8/menu',
  ]

  return {
    name: 'spa-route-shells',
    closeBundle() {
      const outDir = resolve(__dirname, 'dist')
      const index = resolve(outDir, 'index.html')
      if (!existsSync(index)) {
        throw new Error('spa-route-shells: dist/index.html missing after build')
      }
      copyFileSync(index, resolve(outDir, '200.html'))
      copyFileSync(index, resolve(outDir, '404.html'))
      for (const dir of routeDirs) {
        const target = resolve(outDir, dir, 'index.html')
        mkdirSync(dirname(target), { recursive: true })
        copyFileSync(index, target)
      }
    },
  }
}

/**
 * Local dev: /api/proxy?to=base|svc&path=… and /api/cdn?path=… (CDN images)
 */
function eligaProxyPlugin(): Plugin {
  const WEBAPP = 'https://webapp.eligaorder.com'
  const CDN_ORIGIN = 'https://kr.object.ncloudstorage.com/eliga-order/'
  return {
    name: 'eliga-proxy',
    configureServer(server) {
      server.middlewares.use(async (req, res, next) => {
        try {
          const raw = req.url || '/'
          if (raw.startsWith('/api/cdn')) {
            const u = new URL(raw, 'http://localhost')
            const pathRaw = (u.searchParams.get('path') || '').replace(
              /^\/+/,
              '',
            )
            if (
              !pathRaw ||
              pathRaw.includes('..') ||
              pathRaw.includes('://') ||
              pathRaw.startsWith('//')
            ) {
              res.statusCode = 400
              res.end(JSON.stringify({ error: 'bad_path' }))
              return
            }
            let decoded: string
            try {
              decoded = decodeURIComponent(pathRaw)
            } catch {
              res.statusCode = 400
              res.end(JSON.stringify({ error: 'bad_path' }))
              return
            }
            const encoded = decoded
              .split('/')
              .filter(Boolean)
              .map((s) => encodeURIComponent(s))
              .join('/')
            const target = `${CDN_ORIGIN}${encoded}`
            const hostOk = new URL(target)
            if (
              hostOk.hostname !== 'kr.object.ncloudstorage.com' ||
              hostOk.protocol !== 'https:'
            ) {
              res.statusCode = 400
              res.end(JSON.stringify({ error: 'host_not_allowed' }))
              return
            }
            const up = await fetch(target, {
              headers: { Accept: 'image/*,*/*' },
            })
            const buf = Buffer.from(await up.arrayBuffer())
            const ct = (up.headers.get('content-type') || 'image/jpeg')
              .split(';')[0]
              .trim()
              .toLowerCase()
            if (!ct.startsWith('image/')) {
              res.statusCode = 415
              res.end(JSON.stringify({ error: 'unsupported_media_type' }))
              return
            }
            res.statusCode = up.status
            res.setHeader('Content-Type', ct)
            res.setHeader('X-Content-Type-Options', 'nosniff')
            res.setHeader('Cache-Control', 'public, max-age=3600')
            res.end(buf)
            return
          }
          if (!raw.startsWith('/api/proxy')) return next()
          const u = new URL(raw, 'http://localhost')
          const to = u.searchParams.get('to')
          const path = (u.searchParams.get('path') || '').replace(/^\/+/, '')
          const upstream =
            to === 'base'
              ? 'https://base.eligaorder.com'
              : to === 'svc'
                ? 'https://svc.eligaorder.com'
                : null
          if (
            !upstream ||
            !path ||
            path.includes('..') ||
            path.includes('://') ||
            path.startsWith('//') ||
            !/^[a-zA-Z0-9._\-/:%]+$/.test(path)
          ) {
            res.statusCode = 400
            res.end(JSON.stringify({ error: 'bad proxy query' }))
            return
          }
          u.searchParams.delete('to')
          u.searchParams.delete('path')
          const qs = u.searchParams.toString()
          const target = `${upstream}/${path}${qs ? `?${qs}` : ''}`
          const targetUrl = new URL(target)
          if (
            targetUrl.hostname !== new URL(upstream).hostname ||
            targetUrl.protocol !== 'https:'
          ) {
            res.statusCode = 400
            res.end(JSON.stringify({ error: 'host_not_allowed' }))
            return
          }

          const chunks: Buffer[] = []
          let size = 0
          for await (const c of req) {
            size += (c as Buffer).length
            if (size > 512 * 1024) {
              res.statusCode = 413
              res.end(JSON.stringify({ error: 'payload_too_large' }))
              return
            }
            chunks.push(c as Buffer)
          }
          const body = Buffer.concat(chunks)

          const headers: Record<string, string> = {
            Accept: String(req.headers.accept || 'application/json'),
            'User-Agent': req.headers['user-agent'] || 'vite-eliga-proxy',
            Origin: WEBAPP,
            Referer: `${WEBAPP}/`,
          }
          const ct = req.headers['content-type']
          if (ct && String(ct).toLowerCase().includes('application/json')) {
            headers['Content-Type'] = String(ct)
          }
          if (req.headers.cookie) headers.Cookie = String(req.headers.cookie)
          if (
            req.headers.authorization &&
            /^Bearer\s+\S+/i.test(String(req.headers.authorization))
          ) {
            headers.Authorization = String(req.headers.authorization)
          }
          if (body.length) headers['Content-Length'] = String(body.length)

          const up = await fetch(target, {
            method: req.method || 'GET',
            headers,
            body: body.length ? body : undefined,
          })
          const text = await up.text()
          res.statusCode = up.status
          res.setHeader('Content-Type', up.headers.get('content-type') || 'application/json')
          const setCookie = up.headers.getSetCookie?.() || []
          for (const c of setCookie) {
            res.appendHeader?.(
              'Set-Cookie',
              c
                .replace(/;\s*Domain=[^;]*/gi, '')
                .replace(/;\s*SameSite=[^;]*/gi, '')
                .concat('; SameSite=Lax; Path=/'),
            )
          }
          res.end(text)
        } catch (e) {
          res.statusCode = 502
          res.end(JSON.stringify({ error: String(e) }))
        }
      })
    },
  }
}

export default defineConfig(() => {
  const base = process.env.VITE_BASE || '/'

  return {
    plugins: [react(), spaRouteShells(), eligaProxyPlugin()],
    base,
    test: {
      environment: 'node',
      include: ['src/**/*.test.ts', 'api/**/*.test.ts'],
    },
  }
})
