import type { AuthTokens } from './types'

const TOKEN_KEY = 'eliga.auth.tokens'
const LAST_SHOP_KEY = 'eliga.lastShopId'
const SPACE_KEY = 'eliga.spaceUrl'
const USER_KEY = 'eliga.userId'

function sessionGet(key: string): string | null {
  try {
    return sessionStorage.getItem(key)
  } catch {
    return null
  }
}

function sessionSet(key: string, value: string): void {
  try {
    sessionStorage.setItem(key, value)
  } catch {
    /* ignore quota / private mode */
  }
}

function sessionRemove(key: string): void {
  try {
    sessionStorage.removeItem(key)
  } catch {
    /* ignore */
  }
}

function localGet(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

function localSet(key: string, value: string): void {
  try {
    localStorage.setItem(key, value)
  } catch {
    /* ignore */
  }
}

export function loadTokens(): AuthTokens | null {
  const raw = sessionGet(TOKEN_KEY)
  if (!raw) return null
  try {
    const parsed = JSON.parse(raw) as AuthTokens
    if (parsed?.accessToken) return parsed
  } catch {
    /* bad json */
  }
  return null
}

export function saveTokens(tokens: AuthTokens): void {
  sessionSet(TOKEN_KEY, JSON.stringify(tokens))
}

export function clearTokens(): void {
  sessionRemove(TOKEN_KEY)
}

export function loadLastShopId(): number | null {
  const v = localGet(LAST_SHOP_KEY)
  if (v == null) return null
  const n = Number(v)
  return Number.isFinite(n) ? n : null
}

export function saveLastShopId(shopId: number): void {
  localSet(LAST_SHOP_KEY, String(shopId))
}

export function loadSpaceUrl(): string | null {
  return sessionGet(SPACE_KEY)
}

export function saveSpaceUrl(space: string): void {
  sessionSet(SPACE_KEY, space)
}

export function loadRememberedUserId(): string {
  return localGet(USER_KEY) ?? ''
}

export function saveRememberedUserId(userId: string): void {
  localSet(USER_KEY, userId)
}
