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
 * Local dev: /api/proxy?to=base&path=space → upstream
 */
function eligaProxyPlugin(): Plugin {
  const WEBAPP = 'https://webapp.eligaorder.com'
  return {
    name: 'eliga-proxy',
    configureServer(server) {
      server.middlewares.use(async (req, res, next) => {
        try {
          const raw = req.url || '/'
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
          if (!upstream || !path) {
            res.statusCode = 400
            res.end(JSON.stringify({ error: 'bad proxy query' }))
            return
          }
          u.searchParams.delete('to')
          u.searchParams.delete('path')
          const qs = u.searchParams.toString()
          const target = `${upstream}/${path}${qs ? `?${qs}` : ''}`

          const chunks: Buffer[] = []
          for await (const c of req) chunks.push(c as Buffer)
          const body = Buffer.concat(chunks)

          const headers: Record<string, string> = {
            Accept: String(req.headers.accept || 'application/json'),
            'User-Agent': req.headers['user-agent'] || 'vite-eliga-proxy',
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
