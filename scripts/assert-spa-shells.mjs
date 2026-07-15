/**
 * Build gate: LIFT needs per-route index.html shells (spa 200.html rewrite is unreliable).
 */
import { accessSync, constants } from 'node:fs'
import { resolve } from 'node:path'

const required = [
  'dist/index.html',
  'dist/200.html',
  'dist/404.html',
  'dist/login/index.html',
  'dist/cart/index.html',
  'dist/orders/index.html',
  'dist/order/confirm/index.html',
  'dist/dining/7/index.html',
  'dist/cafe/5/index.html',
  'dist/cafe/5/menu/index.html',
  'dist/cafe/3/index.html',
  'dist/cafe/4/index.html',
  'dist/cafe/8/index.html',
]

const root = resolve(import.meta.dirname, '..')
for (const rel of required) {
  const abs = resolve(root, rel)
  try {
    accessSync(abs, constants.R_OK)
  } catch {
    console.error(`Missing SPA shell: ${rel}`)
    process.exit(1)
  }
}
console.log(`SPA shells OK (${required.length} paths)`)
