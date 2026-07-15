import type { AuthTokens } from './types'

const TOKEN_KEY = 'eliga.auth.tokens'
const SESSION_KEY = 'eliga.auth.session'
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
    /* ignore */
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

/**
 * Auth tokens live in localStorage so refresh survives tab close / reload.
 * Session flag is mirrored in both storages for cookie-session mode.
 */
export function loadTokens(): AuthTokens | null {
  const raw = localGet(TOKEN_KEY) ?? sessionGet(TOKEN_KEY)
  if (!raw) return null
  try {
    const parsed = JSON.parse(raw) as AuthTokens
    if (parsed?.accessToken) {
      // Migrate sessionStorage-only tokens to localStorage once
      if (!localGet(TOKEN_KEY)) {
        try {
          localSet(TOKEN_KEY, raw)
        } catch {
          /* ignore */
        }
      }
      return parsed
    }
  } catch {
    /* bad json */
  }
  return null
}

export function saveTokens(tokens: AuthTokens): void {
  // Never persist empty / non-string tokens
  if (
    !tokens?.accessToken ||
    typeof tokens.accessToken !== 'string' ||
    tokens.accessToken.length < 16
  ) {
    return
  }
  const safe: AuthTokens = {
    accessToken: tokens.accessToken,
    refreshToken:
      typeof tokens.refreshToken === 'string' ? tokens.refreshToken : '',
    tokenType:
      typeof tokens.tokenType === 'string' ? tokens.tokenType : 'Bearer',
  }
  const raw = JSON.stringify(safe)
  localSet(TOKEN_KEY, raw)
  sessionSet(TOKEN_KEY, raw)
  localSet(SESSION_KEY, '1')
  sessionSet(SESSION_KEY, '1')
}

export function clearTokens(): void {
  try {
    localStorage.removeItem(TOKEN_KEY)
    localStorage.removeItem(SESSION_KEY)
  } catch {
    /* ignore */
  }
  sessionRemove(TOKEN_KEY)
  sessionRemove(SESSION_KEY)
}

/** Cookie-session flag when AccessToken is HttpOnly and not readable by JS. */
export function loadSessionFlag(): boolean {
  return (
    localGet(SESSION_KEY) === '1' ||
    sessionGet(SESSION_KEY) === '1' ||
    Boolean(loadTokens()?.accessToken)
  )
}

export function saveSessionFlag(on: boolean): void {
  if (on) {
    localSet(SESSION_KEY, '1')
    sessionSet(SESSION_KEY, '1')
  } else {
    try {
      localStorage.removeItem(SESSION_KEY)
    } catch {
      /* ignore */
    }
    sessionRemove(SESSION_KEY)
  }
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
