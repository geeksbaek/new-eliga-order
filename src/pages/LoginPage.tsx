import { useState, type FormEvent } from 'react'
import { Navigate, useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { ErrorBox } from '../components/UiState'

export function LoginPage() {
  const { authed, ready, userId, login } = useAuth()
  const [email, setEmail] = useState(userId)
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const navigate = useNavigate()
  const location = useLocation()
  const from =
    (location.state as { from?: string } | null)?.from || '/'

  if (ready && authed) {
    return <Navigate to={from} replace />
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setBusy(true)
    try {
      await login(email, password)
      navigate(from, { replace: true })
    } catch (err) {
      const msg =
        err instanceof Error ? err.message : '로그인에 실패했습니다'
      setError(
        `${msg}. 카카오 사내 엘리가 계정(이메일/비밀번호)을 확인하세요. 브라우저 CORS로 직접 호출이 막히면 로컬 개발 서버(proxy)를 사용하세요.`,
      )
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="login-wrap">
      <form className="card login-card" onSubmit={onSubmit}>
        <div className="brand" style={{ marginBottom: 16 }}>
          <span className="brand-mark">E</span>
          <span>new 엘리가오더</span>
        </div>
        <h1>로그인</h1>
        <p className="lead">
          사내 엘리가 계정으로 로그인하면 카페 주문과 식당 식단을 볼 수 있습니다.
        </p>

        {error && <ErrorBox>{error}</ErrorBox>}

        <div className="stack" style={{ marginTop: 12 }}>
          <div className="field">
            <label htmlFor="email">이메일</label>
            <input
              id="email"
              name="email"
              type="email"
              autoComplete="username"
              inputMode="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="name@kakaocorp.com"
            />
          </div>
          <div className="field">
            <label htmlFor="password">비밀번호</label>
            <input
              id="password"
              name="password"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="비밀번호"
            />
          </div>
          <button
            type="submit"
            className="btn btn-primary btn-block"
            disabled={busy || !email || !password}
          >
            {busy ? '로그인 중…' : '로그인'}
          </button>
        </div>
      </form>
    </div>
  )
}
