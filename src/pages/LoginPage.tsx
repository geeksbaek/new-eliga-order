import { useId, useState, type FormEvent } from 'react'
import { Navigate, useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { ErrorBox } from '../components/UiState'
import { useApiProxy } from '../api/client'
import { IconCup } from '../components/Icons'

export function LoginPage() {
  const { authed, ready, userId, login } = useAuth()
  const [email, setEmail] = useState(userId)
  const [password, setPassword] = useState('')
  const [showPw, setShowPw] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const navigate = useNavigate()
  const location = useLocation()
  const from = (location.state as { from?: string } | null)?.from || '/'
  const proxy = useApiProxy()
  const emailId = useId()
  const passwordId = useId()

  if (ready && authed) {
    return <Navigate to={from} replace />
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    if (busy) return
    setError(null)
    setBusy(true)
    try {
      await login(email.trim(), password)
      navigate(from, { replace: true })
    } catch (err) {
      const msg =
        err instanceof Error ? err.message : '로그인에 실패했습니다'
      setError(msg)
    } finally {
      setBusy(false)
    }
  }

  const canSubmit = Boolean(email.trim() && password && !busy)

  return (
    <div className="login-shell">
      <header className="login-top">
        <div className="login-brand" aria-label="엘리가오더">
          <span className="login-mark" aria-hidden>
            <IconCup size={18} />
          </span>
          <div className="login-brand-text">
            <strong>엘리가오더</strong>
            <span>사내 식당 · 카페 주문</span>
          </div>
        </div>
      </header>

      <main className="login-main">
        <div className="login-intro">
          <h1 className="login-title">로그인</h1>
          <p className="login-lead">
            엘리가오더 계정으로 입장합니다. 카카오 사내 계정과 동일합니다.
          </p>
        </div>

        {!proxy && (
          <div className="login-banner login-banner-warn" role="status">
            API 프록시가 꺼져 있습니다. 로컬에서는 <code>npm run dev</code> 또는{' '}
            <code>npm start</code>로 실행해 주세요.
          </div>
        )}

        {error && (
          <div className="login-error">
            <ErrorBox>{error}</ErrorBox>
          </div>
        )}

        <form className="login-form" onSubmit={onSubmit} noValidate>
          <div className="field">
            <label htmlFor={emailId}>이메일</label>
            <input
              id={emailId}
              name="email"
              type="email"
              autoComplete="username"
              inputMode="email"
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="name@kakaocorp.com"
              disabled={busy}
            />
          </div>

          <div className="field">
            <label htmlFor={passwordId}>비밀번호</label>
            <div className="login-pw-wrap">
              <input
                id={passwordId}
                name="password"
                type={showPw ? 'text' : 'password'}
                autoComplete="current-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="비밀번호"
                disabled={busy}
              />
              <button
                type="button"
                className="login-pw-toggle"
                onClick={() => setShowPw((v) => !v)}
                aria-pressed={showPw}
                aria-label={showPw ? '비밀번호 숨기기' : '비밀번호 보기'}
                tabIndex={-1}
              >
                {showPw ? '숨김' : '보기'}
              </button>
            </div>
          </div>

          <button
            type="submit"
            className="btn btn-primary btn-block login-submit"
            disabled={!canSubmit}
          >
            {busy ? (
              <>
                <span className="login-submit-spinner" aria-hidden />
                확인 중…
              </>
            ) : (
              '로그인'
            )}
          </button>
        </form>
      </main>

      <footer className="login-foot">
        <p className="login-foot-muted">
          비밀번호를 잊었다면 사내 계정 관리 절차를 따라 주세요.
        </p>
      </footer>
    </div>
  )
}
