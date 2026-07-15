/// <reference types="vitest/config" />
import { copyFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'

// LIFT static share path when building with VITE_BASE=/share/new-eliga-order/
const SITE_ID = 'new-eliga-order'
const DEFAULT_LIFT_BASE = `/share/${SITE_ID}/`

/**
 * LIFT static host does not rewrite unknown paths to 200.html.
 * Emit an index.html shell under every client route directory.
 */
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
      // GitHub Pages SPA fallback
      copyFileSync(index, resolve(outDir, '404.html'))
      for (const dir of routeDirs) {
        const target = resolve(outDir, dir, 'index.html')
        mkdirSync(dirname(target), { recursive: true })
        copyFileSync(index, target)
      }
    },
  }
}

export default defineConfig(() => {
  // Vercel / local: base "/". LIFT: VITE_BASE=/share/new-eliga-order/ npm run build:lift
  const base =
    process.env.VITE_BASE ||
    (process.env.LIFT_BUILD === '1' ? DEFAULT_LIFT_BASE : '/')

  return {
    plugins: [react(), spaRouteShells()],
    base,
    server: {
      proxy: {
        '/__eliga-base': {
          target: 'https://base.eligaorder.com',
          changeOrigin: true,
          rewrite: (p) => p.replace(/^\/__eliga-base/, ''),
        },
        '/__eliga-svc': {
          target: 'https://svc.eligaorder.com',
          changeOrigin: true,
          rewrite: (p) => p.replace(/^\/__eliga-svc/, ''),
          configure: (proxy) => {
            proxy.on('proxyReq', (proxyReq) => {
              proxyReq.setHeader('Origin', 'https://webapp.eligaorder.com')
              proxyReq.setHeader('Referer', 'https://webapp.eligaorder.com/')
            })
          },
        },
      },
    },
    test: {
      environment: 'node',
      include: ['src/**/*.test.ts'],
    },
  }
})
