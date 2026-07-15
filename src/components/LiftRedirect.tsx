import { useEffect, useState } from 'react'
import {
  getCanonicalAppUrl,
  isLiftHost,
} from '../api/client'

/**
 * LIFT enforces CSP default-src 'self' without connect-src to Eliga APIs.
 * Redirect to the canonical host that proxies /__eliga-* same-origin.
 */
export function LiftRedirectGate({ children }: { children: React.ReactNode }) {
  const [onLift] = useState(() =>
    typeof window !== 'undefined' ? isLiftHost() : false,
  )
  const dest = getCanonicalAppUrl()

  useEffect(() => {
    if (!onLift) return
    const path = window.location.pathname.replace(
      /^\/share\/new-eliga-order\/?/,
      '/',
    )
    const target = `${dest}${path === '/' ? '/' : path}${window.location.search}${window.location.hash}`
    // Immediate navigation — keep a short message for slow networks
    window.location.replace(target)
  }, [onLift, dest])

  if (!onLift) return <>{children}</>

  return (
    <div className="login-wrap">
      <div className="card login-card">
        <div className="brand" style={{ marginBottom: 12 }}>
          <span className="brand-mark">E</span>
          <span>new 엘리가오더</span>
        </div>
        <h1>연결 중…</h1>
        <p className="lead">
          LIFT 정적 호스트는 Content-Security-Policy 때문에 엘리가 API에 연결할 수
          없습니다. API 프록시가 있는 주소로 이동합니다.
        </p>
        <a className="btn btn-primary btn-block" href={dest}>
          {dest} 로 이동
        </a>
      </div>
    </div>
  )
}
