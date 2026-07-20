/**
 * App-wide text size preference (localStorage).
 * Applied as a class on <html> so rem-based UI scales together.
 */

export type TextSize = 'normal' | 'large'

const KEY = 'eliga.ui.textSize'
export const TEXT_SIZE_CLASS = 'text-size-large'

export function loadTextSize(): TextSize {
  try {
    const v = localStorage.getItem(KEY)
    if (v === 'large') return 'large'
  } catch {
    /* ignore */
  }
  return 'normal'
}

export function saveTextSize(size: TextSize): void {
  try {
    if (size === 'normal') localStorage.removeItem(KEY)
    else localStorage.setItem(KEY, size)
  } catch {
    /* ignore */
  }
  applyTextSize(size)
}

/** Sync documentElement class with preference. */
export function applyTextSize(size: TextSize = loadTextSize()): void {
  if (typeof document === 'undefined') return
  document.documentElement.classList.toggle(TEXT_SIZE_CLASS, size === 'large')
}
