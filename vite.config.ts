/// <reference types="vitest/config" />
import { copyFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'

/** Default public path for GitHub Pages project site. */
const DEFAULT_PAGES_BASE = '/new-eliga-order/'

/**
 * Emit index.html shells under client routes + 404.html for static hosts.
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
  // Override with VITE_BASE=/ for local preview at root if needed
  const base = process.env.VITE_BASE || DEFAULT_PAGES_BASE

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
