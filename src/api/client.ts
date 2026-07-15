/**
 * Eliga HTTP client — paths match eliga-api.sh / api-reference.md.
 *
 * Auth (same as eliga-api.sh): HttpOnly AccessToken cookie on .eligaorder.com.
 * Browser must call via same-origin proxy so cookies are first-party:
 *   /__eliga-base → https://base.eligaorder.com
 *   /__eliga-svc  → https://svc.eligaorder.com
 * (Vite dev proxy or `node server.mjs`)
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
export const CDN_URL =
  'https://eliga-ordercdn.object.ncloudstorage.com/'

export const PROXY_BASE = '/__eliga-base'
export const PROXY_SVC = '/__eliga-svc'

/**
 * Always prefer same-origin proxy. Direct host calls cannot use HttpOnly
 * AccessToken cookies across sites (GitHub Pages → eligaorder.com is third-party).
 */
export function useApiProxy(): boolean {
  if (import.meta.env.VITE_USE_PROXY === 'false') return false
  return true
}

export function baseApiRoot(): string {
  return useApiProxy() ? PROXY_BASE : BASE_HOST
}

export function svcApiRoot(space: string): string {
  const root = useApiProxy() ? PROXY_SVC : SVC_HOST
  return `${root}/${space}`
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
  if (/Failed to fetch|NetworkError|Load failed|404/i.test(msg)) {
    return (
      'API 프록시에 연결하지 못했습니다. 로컬에서 `npm run dev` 또는 `npm run build && npm start` 로 실행하세요. ' +
      '(GitHub Pages 단독 호스팅은 엘리가 쿠키 인증을 지원하지 않습니다.)'
    )
  }
  return msg || '네트워크 오류'
}

/** Pull access/refresh tokens from various successful sign-in body shapes. */
export function extractTokensFromSignInBody(data: unknown): AuthTokens | null {
  if (!data || typeof data !== 'object') return null
  const root = data as Record<string, unknown>
  const candidates: unknown[] = [
    root.content,
    root.data,
    root.result,
    root,
  ]
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
    // nested token object
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
  const url = `${baseApiRoot()}/space?brandCode=${encodeURIComponent(BRAND_CODE)}`
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
    throw new ApiError('space resolve failed', res.status, await safeJson(res))
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

export async function apiRequest<T = unknown>(
  path: string,
  options: RequestOptions = {},
): Promise<T> {
  const space = await resolveSpace()
  const method = options.method ?? 'GET'
  const headers = authHeaders(options.auth !== false)
  if (options.body !== undefined) {
    headers['Content-Type'] = 'application/json'
  }

  const url = `${svcApiRoot(space)}${path.startsWith('/') ? path : `/${path}`}`
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
    setSessionAuthed(false)
    throw new ApiError('로그인이 필요합니다', 401, await safeJson(res))
  }

  if (!res.ok) {
    const body = await safeJson(res)
    let msg = `요청 실패 (${res.status})`
    if (body && typeof body === 'object') {
      const rec = body as { content?: unknown; message?: unknown; code?: unknown }
      const detail = rec.content ?? rec.message ?? rec.code
      if (detail != null && detail !== '') {
        msg = typeof detail === 'string' ? detail : JSON.stringify(detail)
      }
    }
    throw new ApiError(msg, res.status, body)
  }

  if (res.status === 204) return undefined as T
  return (await res.json()) as T
}

export async function signIn(
  userId: string,
  password: string,
): Promise<AuthTokens | { cookieSession: true }> {
  const space = await resolveSpace()
  const url = `${svcApiRoot(space)}/customer/sign-in`
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
    let msg = '로그인에 실패했습니다'
    if (data && typeof data === 'object') {
      const rec = data as { content?: unknown; message?: unknown; code?: unknown }
      const detail = rec.content ?? rec.message ?? rec.code
      if (typeof detail === 'string' && detail) msg = detail
    }
    throw new ApiError(msg, res.status, data)
  }

  // Prefer JSON tokens when present (proxy may inject AccessToken from Set-Cookie)
  const tokens = extractTokensFromSignInBody(data)
  if (tokens?.accessToken) {
    setAuthTokens(tokens)
    await assertSessionWorks()
    return tokens
  }

  // Official web/CLI path: HttpOnly AccessToken cookie only — no body token
  setSessionAuthed(true)
  try {
    await assertSessionWorks()
  } catch (e) {
    setSessionAuthed(false)
    throw new ApiError(
      '로그인 응답은 왔지만 세션 쿠키가 유지되지 않았습니다. ' +
        '`npm run dev` 또는 `npm start`(API 프록시)로 실행해야 합니다. ' +
        'GitHub Pages 정적 호스팅만으로는 엘리가 쿠키 인증이 동작하지 않습니다.',
      401,
      e,
    )
  }
  return { cookieSession: true }
}

/** Confirm session with /customer/me (cookie and/or Bearer). */
async function assertSessionWorks(): Promise<void> {
  const space = await resolveSpace()
  const url = `${svcApiRoot(space)}/customer/me`
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
    const data = await apiRequest<{ content: AuthTokens }>(
      '/customer/refresh-token',
      {
        method: 'POST',
        body: { refreshToken: current.refreshToken },
        auth: false,
      },
    )
    const tokens = extractTokensFromSignInBody(data)
    if (tokens?.accessToken) {
      setAuthTokens(tokens)
      return tokens
    }
  } catch {
    setSessionAuthed(false)
  }
  return null
}

export function cdnUrl(path: string | null | undefined): string | null {
  if (!path) return null
  if (path.startsWith('http')) return path
  return `${CDN_URL}${path.replace(/^\//, '')}`
}
