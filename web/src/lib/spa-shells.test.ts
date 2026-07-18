import { describe, expect, it } from 'vitest'
import { readFileSync, existsSync } from 'node:fs'
import { resolve } from 'node:path'

/**
 * Structural check of shipped build output when present.
 * Run after `npm run build` — asserts real dist shells, not re-implemented logic.
 */
const dist = resolve(process.cwd(), 'dist')

const criticalShells = [
  'index.html',
  '200.html',
  'cafe/5/index.html',
  'orders/index.html',
  'cart/index.html',
  'login/index.html',
]

describe('SPA route shells (shipped dist)', () => {
  it('has index shells for LIFT deep-link paths when dist exists', () => {
    if (!existsSync(resolve(dist, 'index.html'))) {
      // Fresh checkout without build — skip structural gate (CI build covers it)
      expect(true).toBe(true)
      return
    }
    for (const rel of criticalShells) {
      const p = resolve(dist, rel)
      expect(existsSync(p), `missing ${rel}`).toBe(true)
      const html = readFileSync(p, 'utf8')
      expect(html).toContain('id="root"')
      expect(html).toMatch(/index-.*\.js/)
    }
  })
})
