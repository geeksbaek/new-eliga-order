import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import {
  isAuthenticated,
  onAuthChange,
  setAuthTokens,
} from '../api/client'
import { login as apiLogin } from '../api/eliga'
import {
  loadRememberedUserId,
  saveRememberedUserId,
} from '../lib/storage'

interface AuthContextValue {
  ready: boolean
  authed: boolean
  userId: string
  login: (userId: string, password: string) => Promise<void>
  logout: () => void
  setUserIdHint: (id: string) => void
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(false)
  const [authed, setAuthed] = useState(false)
  const [userId, setUserId] = useState('')

  useEffect(() => {
    setAuthed(isAuthenticated())
    setUserId(loadRememberedUserId())
    setReady(true)
    return onAuthChange((tokens) => setAuthed(Boolean(tokens?.accessToken)))
  }, [])

  const login = useCallback(async (id: string, password: string) => {
    await apiLogin(id.trim(), password)
    saveRememberedUserId(id.trim())
    setUserId(id.trim())
    setAuthed(true)
  }, [])

  const logout = useCallback(() => {
    setAuthTokens(null)
    setAuthed(false)
  }, [])

  const setUserIdHint = useCallback((id: string) => {
    setUserId(id)
    saveRememberedUserId(id)
  }, [])

  const value = useMemo(
    () => ({ ready, authed, userId, login, logout, setUserIdHint }),
    [ready, authed, userId, login, logout, setUserIdHint],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within AuthProvider')
  return ctx
}
