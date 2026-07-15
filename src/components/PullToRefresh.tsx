import type { PullToRefreshState } from '../hooks/usePullToRefresh'
import { PTR_THRESHOLD } from '../hooks/usePullToRefresh'

type Props = {
  state: PullToRefreshState
}

/**
 * Fixed top indicator for custom PWA pull-to-refresh.
 * Render only when `usePullToRefresh` is active (standalone).
 */
export function PullToRefreshIndicator({ state }: Props) {
  const { pull, armed, refreshing } = state
  if (pull <= 0 && !refreshing) return null

  const progress = Math.min(1, pull / PTR_THRESHOLD)
  const y = refreshing ? PTR_THRESHOLD : pull

  return (
    <div
      className={`ptr-root${refreshing ? ' is-refreshing' : ''}${armed ? ' is-armed' : ''}`}
      style={{ transform: `translate3d(0, ${y}px, 0)` }}
      aria-hidden
    >
      <div
        className="ptr-badge"
        style={
          refreshing
            ? undefined
            : { opacity: 0.35 + progress * 0.65, transform: `rotate(${progress * 240}deg)` }
        }
      >
        <span className="ptr-spinner" />
      </div>
    </div>
  )
}
