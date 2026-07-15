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

/** Lightweight skeleton block for soft loading states */
export function Skeleton({
  height = 16,
  width = '100%',
  radius = 10,
  className = '',
}: {
  height?: number | string
  width?: number | string
  radius?: number
  className?: string
}) {
  return (
    <div
      className={`skeleton ${className}`.trim()}
      style={{ height, width, borderRadius: radius }}
      aria-hidden
    />
  )
}

export function SkeletonList({ rows = 4 }: { rows?: number }) {
  return (
    <div className="skeleton-list" aria-busy="true" aria-live="polite">
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className="skeleton-row skeleton-row-dining">
          <Skeleton height={44} width={44} radius={8} />
          <div className="skeleton-row-body">
            <Skeleton height={12} width="30%" />
            <Skeleton height={16} width="72%" />
          </div>
        </div>
      ))}
    </div>
  )
}
