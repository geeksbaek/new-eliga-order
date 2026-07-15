export function Loading({ label = '불러오는 중…' }: { label?: string }) {
  return (
    <div className="loading" role="status" aria-live="polite">
      <div className="spinner" aria-hidden />
      <span>{label}</span>
    </div>
  )
}

export function Empty({ children }: { children: React.ReactNode }) {
  return <div className="empty">{children}</div>
}

export function ErrorBox({ children }: { children: React.ReactNode }) {
  return (
    <div className="error-box" role="alert">
      {children}
    </div>
  )
}

export function InfoBox({ children }: { children: React.ReactNode }) {
  return <div className="info-box">{children}</div>
}
