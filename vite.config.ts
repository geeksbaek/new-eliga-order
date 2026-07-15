/// <reference types="vitest/config" />
import { copyFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'

/**
 * Emit index.html shells under client routes for hard-refresh on static hosts.
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
      copyFileSync(index, resolve(outDir, '404.html'))
      for (const dir of routeDirs) {
        const target = resolve(outDir, dir, 'index.html')
        mkdirSync(dirname(target), { recursive: true })
        copyFileSync(index, target)
      }
    },
  }
}

const eligaProxy = {
  '/__eliga-base': {
    target: 'https://base.eligaorder.com',
    changeOrigin: true,
    rewrite: (p: string) => p.replace(/^\/__eliga-base/, ''),
  },
  '/__eliga-svc': {
    target: 'https://svc.eligaorder.com',
    changeOrigin: true,
    rewrite: (p: string) => p.replace(/^\/__eliga-svc/, ''),
    configure: (proxy: {
      on: (ev: string, fn: (...args: unknown[]) => void) => void
    }) => {
      proxy.on('proxyReq', (...args: unknown[]) => {
        const proxyReq = args[0] as {
          setHeader: (k: string, v: string) => void
        }
        proxyReq.setHeader('Origin', 'https://webapp.eligaorder.com')
        proxyReq.setHeader('Referer', 'https://webapp.eligaorder.com/')
      })
    },
  },
}

export default defineConfig(() => {
  const base = process.env.VITE_BASE || '/'

  return {
    plugins: [react(), spaRouteShells()],
    base,
    server: { proxy: eligaProxy },
    preview: { proxy: eligaProxy },
    test: {
      environment: 'node',
      include: ['src/**/*.test.ts'],
    },
  }
})

