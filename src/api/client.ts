/**
 * Eliga HTTP client — paths match eliga-api.sh / api-reference.md.
 *
 * Production (Vercel): same-origin `/api/proxy?to=base|svc&path=...&...query`
 * Local: Vite middleware / server.mjs handle the same entry.
 */
import {
  clearTokens,
  loadSessionFlag,
  loadSpaceUrl,
  loadTokens,
  saveSessionFlag,
  saveSpaceUrl,
  saveTokens,
} from '../lib/storage'
import type { AuthTokens } from '../lib/types'

export const BRAND_CODE = 'kakao'
export const BASE_HOST = 'https://base.eligaorder.com'
export const SVC_HOST = 'https://svc.eligaorder.com'
export const WEBAPP_ORIGIN = 'https://webapp.eligaorder.com'
export { ELIGA_CDN_BASE as CDN_URL, mediaUrl as cdnUrl } from '../lib/format'

export const PROXY_ENTRY = '/api/proxy'

export function useApiProxy(): boolean {
  if (import.meta.env.VITE_USE_PROXY === 'false') return false
  return true
}

/** Build /api/proxy?to=...&path=...&k=v — path never contains '?'. */
export function proxyUrl(
  to: 'base' | 'svc',
  path: string,
  query?: Record<string, string | number | undefined | null>,
): string {
  const clean = path.replace(/^\/+/, '').split('?')[0]
  const sp = new URLSearchParams()
  sp.set('to', to)
  sp.set('path', clean)
  if (query) {
    for (const [k, v] of Object.entries(query)) {
      if (v == null || v === '') continue
      sp.set(k, String(v))
    }
  }
  return `${PROXY_ENTRY}?${sp.toString()}`
}

/** Split "/goods/display?shopId=5" → path + query map */
export function splitPathQuery(pathWithQuery: string): {
  path: string
  query: Record<string, string>
} {
  const raw = pathWithQuery.startsWith('/')
    ? pathWithQuery.slice(1)
    : pathWithQuery
  const qIdx = raw.indexOf('?')
  if (qIdx < 0) return { path: raw, query: {} }
  const path = raw.slice(0, qIdx)
  const query: Record<string, string> = {}
  new URLSearchParams(raw.slice(qIdx + 1)).forEach((v, k) => {
    query[k] = v
  })
  return { path, query }
}

export class ApiError extends Error {
  status: number
  body: unknown

  constructor(message: string, status: number, body?: unknown) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.body = body
  }
}

type AuthListener = (authed: boolean) => void
const authListeners = new Set<AuthListener>()

export function onAuthChange(fn: AuthListener): () => void {
  authListeners.add(fn)
  return () => authListeners.delete(fn)
}

function notifyAuth(authed: boolean) {
  authListeners.forEach((fn) => fn(authed))
}

export function getAccessToken(): string | null {
  return loadTokens()?.accessToken ?? null
}

export function setAuthTokens(tokens: AuthTokens | null) {
  if (tokens?.accessToken) {
    saveTokens(tokens)
    saveSessionFlag(true)
    notifyAuth(true)
  } else {
    clearTokens()
    saveSessionFlag(false)
    notifyAuth(false)
  }
}

export function setSessionAuthed(on: boolean) {
  if (on) {
    saveSessionFlag(true)
    notifyAuth(true)
  } else {
    clearTokens()
    saveSessionFlag(false)
    notifyAuth(false)
  }
}

export function isAuthenticated(): boolean {
  return loadSessionFlag()
}

const SPACE_RE = /^[a-zA-Z0-9._-]+$/

function networkErrorMessage(err: unknown): string {
  const msg = err instanceof Error ? err.message : String(err)
  if (/Failed to fetch|NetworkError|Load failed/i.test(msg)) {
    return '네트워크 오류가 발생했습니다. 연결을 확인한 뒤 다시 시도해 주세요.'
  }
  return msg || '네트워크 오류'
}

/** Map proxy/upstream failures to a readable Korean message. */
function httpErrorMessage(status: number, body: unknown, fallback: string): string {
  if (body && typeof body === 'object') {
    const rec = body as {
      error?: unknown
      message?: unknown
      content?: unknown
      code?: unknown
    }
    if (rec.error === 'proxy_upstream_failed' || status === 502) {
      return (
        '엘리가 서버에 연결하지 못했습니다. ' +
        '잠시 후 다시 시도해 주세요. 계속되면 네트워크 상태를 확인해 주세요.'
      )
    }
    const detail = rec.content ?? rec.message ?? rec.code
    if (typeof detail === 'string' && detail.trim()) return detail
  }
  return fallback
}

export function extractTokensFromSignInBody(data: unknown): AuthTokens | null {
  if (!data || typeof data !== 'object') return null
  const root = data as Record<string, unknown>
  const candidates: unknown[] = [root.content, root.data, root.result, root]
  for (const c of candidates) {
    if (!c || typeof c !== 'object') continue
    const o = c as Record<string, unknown>
    const access =
      (typeof o.accessToken === 'string' && o.accessToken) ||
      (typeof o.access_token === 'string' && o.access_token) ||
      (typeof o.token === 'string' && o.token) ||
      null
    if (access) {
      const refresh =
        (typeof o.refreshToken === 'string' && o.refreshToken) ||
        (typeof o.refresh_token === 'string' && o.refresh_token) ||
        ''
      return {
        accessToken: access,
        refreshToken: refresh,
        tokenType: typeof o.tokenType === 'string' ? o.tokenType : 'Bearer',
      }
    }
    if (o.token && typeof o.token === 'object') {
      const nested = extractTokensFromSignInBody({ content: o.token })
      if (nested) return nested
    }
  }
  return null
}

export async function resolveSpace(force = false): Promise<string> {
  if (!force) {
    const cached = loadSpaceUrl()
    if (cached && SPACE_RE.test(cached)) return cached
  }
  const url = useApiProxy()
    ? proxyUrl('base', 'space', { brandCode: BRAND_CODE })
    : `${BASE_HOST}/space?brandCode=${encodeURIComponent(BRAND_CODE)}`
  let res: Response
  try {
    res = await fetch(url, {
      headers: { Accept: 'application/json' },
      credentials: 'include',
    })
  } catch (err) {
    throw new ApiError(networkErrorMessage(err), 0, err)
  }
  if (!res.ok) {
    const body = await safeJson(res)
    throw new ApiError(
      httpErrorMessage(res.status, body, 'space resolve failed'),
      res.status,
      body,
    )
  }
  const data = (await res.json()) as { content?: string }
  const space = data.content
  if (!space || !SPACE_RE.test(space)) {
    throw new ApiError('invalid space response', 500, data)
  }
  saveSpaceUrl(space)
  return space
}

async function safeJson(res: Response): Promise<unknown> {
  try {
    return await res.json()
  } catch {
    return null
  }
}

export interface RequestOptions {
  method?: string
  body?: unknown
  auth?: boolean
  signal?: AbortSignal
  /** Internal: do not try refresh-token again (after one retry). */
  _retried?: boolean
  /** Internal: refresh-token call itself — never trigger another refresh. */
  _isRefresh?: boolean
}

function authHeaders(includeAuth: boolean): Record<string, string> {
  const headers: Record<string, string> = {
    Accept: 'application/json',
  }
  if (includeAuth) {
    const token = getAccessToken()
    if (token) headers.Authorization = `Bearer ${token}`
  }
  return headers
}

/** Single in-flight refresh so parallel 401s share one token exchange. */
let refreshInFlight: Promise<AuthTokens | null> | null = null

async function refreshAccessTokenOnce(): Promise<AuthTokens | null> {
  if (!refreshInFlight) {
    refreshInFlight = refreshAccessToken().finally(() => {
      refreshInFlight = null
    })
  }
  return refreshInFlight
}

/** JWT exp (seconds). Non-JWT access tokens return null. */
function jwtExpSeconds(accessToken: string): number | null {
  try {
    const parts = accessToken.split('.')
    if (parts.length < 2) return null
    const b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/')
    const pad = b64.length % 4 === 0 ? '' : '='.repeat(4 - (b64.length % 4))
    const json = JSON.parse(atob(b64 + pad)) as { exp?: unknown }
    return typeof json.exp === 'number' ? json.exp : null
  } catch {
    return null
  }
}

/**
 * If access JWT expires within `skewSec`, refresh proactively.
 * Keeps UX smooth (fewer mid-action 401s) without changing login flow.
 */
async function ensureAccessTokenFresh(skewSec = 90): Promise<void> {
  const current = loadTokens()
  if (!current?.accessToken || !current.refreshToken) return
  const exp = jwtExpSeconds(current.accessToken)
  if (exp == null) return
  const now = Math.floor(Date.now() / 1000)
  if (exp - now > skewSec) return
  await refreshAccessTokenOnce()
}

export async function apiRequest<T = unknown>(
  pathWithQuery: string,
  options: RequestOptions = {},
): Promise<T> {
  if (options.auth !== false && !options._isRefresh && !options._retried) {
    try {
      await ensureAccessTokenFresh()
    } catch {
      /* fall through — request may still succeed or 401-refresh */
    }
  }

  const space = await resolveSpace()
  const method = options.method ?? 'GET'
  const headers = authHeaders(options.auth !== false)
  if (options.body !== undefined) {
    headers['Content-Type'] = 'application/json'
  }

  const { path, query } = splitPathQuery(pathWithQuery)
  const fullPath = `${space}/${path}`

  const url = useApiProxy()
    ? proxyUrl('svc', fullPath, query)
    : (() => {
        const sp = new URLSearchParams(query)
        const q = sp.toString()
        return `${SVC_HOST}/${fullPath}${q ? `?${q}` : ''}`
      })()

  let res: Response
  try {
    res = await fetch(url, {
      method,
      headers,
      body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
      signal: options.signal,
      credentials: 'include',
    })
  } catch (err) {
    throw new ApiError(networkErrorMessage(err), 0, err)
  }

  if (res.status === 401) {
    // Cookie/JWT session expired — try refresh once (not for the refresh call itself)
    const canRefresh =
      options.auth !== false &&
      !options._retried &&
      !options._isRefresh &&
      Boolean(loadTokens()?.refreshToken)

    if (canRefresh) {
      const next = await refreshAccessTokenOnce()
      if (next?.accessToken) {
        return apiRequest<T>(pathWithQuery, { ...options, _retried: true })
      }
    }

    setSessionAuthed(false)
    throw new ApiError('로그인이 필요합니다', 401, await safeJson(res))
  }

  if (!res.ok) {
    const body = await safeJson(res)
    const msg = httpErrorMessage(
      res.status,
      body,
      `요청 실패 (${res.status})`,
    )
    throw new ApiError(msg, res.status, body)
  }

  if (res.status === 204) return undefined as T
  // empty body
  const text = await res.text()
  if (!text) return undefined as T
  try {
    return JSON.parse(text) as T
  } catch {
    throw new ApiError('응답 JSON 파싱 실패', res.status, text)
  }
}

export async function signIn(
  userId: string,
  password: string,
): Promise<AuthTokens | { cookieSession: true }> {
  const space = await resolveSpace()
  const url = useApiProxy()
    ? proxyUrl('svc', `${space}/customer/sign-in`)
    : `${SVC_HOST}/${space}/customer/sign-in`

  let res: Response
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
      },
      credentials: 'include',
      body: JSON.stringify({
        userId,
        password,
        brandCode: BRAND_CODE,
        fcmToken: 'web-new-eliga-order',
      }),
    })
  } catch (err) {
    throw new ApiError(networkErrorMessage(err), 0, err)
  }

  const data = await safeJson(res)

  if (!res.ok) {
    let msg = httpErrorMessage(res.status, data, '로그인에 실패했습니다')
    if (msg === '로그인에 실패했습니다' && data && typeof data === 'object') {
      const rec = data as { content?: unknown; message?: unknown; code?: unknown }
      const detail = rec.content ?? rec.message ?? rec.code
      if (typeof detail === 'string' && detail) msg = detail
    }
    // Only rewrite known login codes; keep proxy/network messages as-is
    if (!msg.includes('엘리가 서버에 연결')) {
      msg = humanizeLoginError(msg)
    }
    throw new ApiError(msg, res.status, data)
  }

  const tokens = extractTokensFromSignInBody(data)
  if (tokens?.accessToken) {
    setAuthTokens(tokens)
    await assertSessionWorks()
    return tokens
  }

  setSessionAuthed(true)
  try {
    await assertSessionWorks()
  } catch (e) {
    setSessionAuthed(false)
    throw new ApiError(
      '로그인 응답은 왔지만 세션이 유지되지 않았습니다. 다시 로그인해 주세요.',
      401,
      e,
    )
  }
  return { cookieSession: true }
}

async function assertSessionWorks(): Promise<void> {
  const space = await resolveSpace()
  const url = useApiProxy()
    ? proxyUrl('svc', `${space}/customer/me`)
    : `${SVC_HOST}/${space}/customer/me`
  const res = await fetch(url, {
    headers: authHeaders(true),
    credentials: 'include',
  })
  if (!res.ok) {
    throw new ApiError('세션 확인 실패', res.status, await safeJson(res))
  }
}

export async function refreshAccessToken(): Promise<AuthTokens | null> {
  const current = loadTokens()
  if (!current?.refreshToken) return null
  try {
    const data = await apiRequest<unknown>('/customer/refresh-token', {
      method: 'POST',
      body: { refreshToken: current.refreshToken },
      auth: false,
      _isRefresh: true,
    })
    const tokens = extractTokensFromSignInBody(data)
    if (tokens?.accessToken) {
      // Keep previous refreshToken if server omits a new one
      setAuthTokens({
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken || current.refreshToken,
        tokenType: tokens.tokenType ?? current.tokenType,
      })
      return loadTokens()
    }
  } catch {
    /* caller decides whether to log out */
  }
  return null
}

function humanizeLoginError(code: string): string {
  switch (code) {
    case 'LOGIN_USER_NOT_FOUND':
      return '등록되지 않은 계정이거나 이메일 형식이 올바르지 않습니다.'
    case 'LOGIN_PASSWORD_NOT_MATCHED':
    case 'LOGIN_PASSWORD_MISMATCH':
      return '비밀번호가 일치하지 않습니다.'
    case 'LOGIN_USER_LOCKED':
      return '잠긴 계정입니다. 엘리가 앱에서 확인해 주세요.'
    default:
      return code
  }
}
