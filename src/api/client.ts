/**
 * Eliga HTTP client — paths match eliga-api.sh / api-reference.md.
 * Base: https://base.eligaorder.com
 * Service: https://svc.eligaorder.com/{space}
 *
 * Dev: Vite proxy `/__eliga-base` + `/__eliga-svc`.
 * Production (GitHub Pages): direct hosts — Eliga CORS reflects Origin.
 */
import {
  clearTokens,
  loadSpaceUrl,
  loadTokens,
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

/** Same-origin proxy roots (Vite dev server). */
export const PROXY_BASE = '/__eliga-base'
export const PROXY_SVC = '/__eliga-svc'

/** Dev uses Vite proxy; production calls Eliga hosts directly. */
export function useApiProxy(): boolean {
  if (import.meta.env.VITE_USE_PROXY === 'true') return true
  if (import.meta.env.VITE_USE_PROXY === 'false') return false
  return import.meta.env.DEV === true
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

type TokenListener = (tokens: AuthTokens | null) => void
const tokenListeners = new Set<TokenListener>()

export function onAuthChange(fn: TokenListener): () => void {
  tokenListeners.add(fn)
  return () => tokenListeners.delete(fn)
}

function notifyAuth(tokens: AuthTokens | null) {
  tokenListeners.forEach((fn) => fn(tokens))
}

export function getAccessToken(): string | null {
  return loadTokens()?.accessToken ?? null
}

export function setAuthTokens(tokens: AuthTokens | null) {
  if (tokens) saveTokens(tokens)
  else clearTokens()
  notifyAuth(tokens)
}

export function isAuthenticated(): boolean {
  return Boolean(getAccessToken())
}

const SPACE_RE = /^[a-zA-Z0-9._-]+$/

function networkErrorMessage(err: unknown): string {
  const msg = err instanceof Error ? err.message : String(err)
  if (/Failed to fetch|NetworkError|Load failed|Content Security Policy|CSP/i.test(msg)) {
    return '네트워크 연결에 실패했습니다. 사내망/VPN과 브라우저 콘솔을 확인해 주세요.'
  }
  return msg || '네트워크 오류'
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

export async function apiRequest<T = unknown>(
  path: string,
  options: RequestOptions = {},
): Promise<T> {
  const space = await resolveSpace()
  const method = options.method ?? 'GET'
  const headers: Record<string, string> = {
    Accept: 'application/json',
  }
  if (options.body !== undefined) {
    headers['Content-Type'] = 'application/json'
  }
  if (options.auth !== false) {
    const token = getAccessToken()
    if (token) headers.Authorization = `Bearer ${token}`
  }

  const url = `${svcApiRoot(space)}${path.startsWith('/') ? path : `/${path}`}`
  let res: Response
  try {
    res = await fetch(url, {
      method,
      headers,
      body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
      signal: options.signal,
    })
  } catch (err) {
    throw new ApiError(networkErrorMessage(err), 0, err)
  }

  if (res.status === 401) {
    setAuthTokens(null)
    throw new ApiError('로그인이 필요합니다', 401, await safeJson(res))
  }

  if (!res.ok) {
    const body = await safeJson(res)
    let msg = `요청 실패 (${res.status})`
    if (body && typeof body === 'object') {
      const rec = body as { content?: unknown; message?: unknown }
      const detail = rec.content ?? rec.message
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
): Promise<AuthTokens> {
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

  if (!res.ok) {
    const body = await safeJson(res)
    throw new ApiError('로그인에 실패했습니다', res.status, body)
  }

  const data = (await res.json()) as {
    content?: AuthTokens
  }
  const tokens = data.content
  if (!tokens?.accessToken) {
    throw new ApiError('토큰이 응답에 없습니다', 500, data)
  }
  setAuthTokens(tokens)
  return tokens
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
    if (data?.content?.accessToken) {
      setAuthTokens(data.content)
      return data.content
    }
  } catch {
    setAuthTokens(null)
  }
  return null
}

export function cdnUrl(path: string | null | undefined): string | null {
  if (!path) return null
  if (path.startsWith('http')) return path
  return `${CDN_URL}${path.replace(/^\//, '')}`
}
