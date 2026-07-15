import type { ReactNode } from 'react'
import { BackButton } from './BackButton'

type BackProps = {
  fallbackTo?: string
  label?: string
  onClick?: () => void
}

type Props = {
  title: ReactNode
  /** Small line above title (e.g. date) */
  kicker?: ReactNode
  /** Muted line under title */
  sub?: ReactNode
  /** Right-side actions */
  trailing?: ReactNode
  /** When set, shows back control in the header row */
  back?: BackProps | true
  className?: string
}

/**
 * Single header shell for every page.
 * Layout: [back?] [main: kicker/title/sub] [trailing?]
 */
export function PageHeader({
  title,
  kicker,
  sub,
  trailing,
  back,
  className = '',
}: Props) {
  const backProps: BackProps | null =
    back === true ? { fallbackTo: '/', label: '뒤로' } : back ?? null

  return (
    <header
      className={['page-header', backProps ? 'has-back' : '', className]
        .filter(Boolean)
        .join(' ')}
    >
      <div className="page-header-row">
        {backProps && (
          <div className="page-header-back">
            <BackButton
              fallbackTo={backProps.fallbackTo}
              label={backProps.label}
              onClick={backProps.onClick}
            />
          </div>
        )}
        <div className="page-header-main">
          {kicker != null && kicker !== false && (
            <p className="page-header-kicker">{kicker}</p>
          )}
          <h1 className="page-header-title">{title}</h1>
          {sub != null && sub !== false && (
            <p className="page-header-sub">{sub}</p>
          )}
        </div>
        {trailing != null && (
          <div className="page-header-trailing">{trailing}</div>
        )}
      </div>
    </header>
  )
}
