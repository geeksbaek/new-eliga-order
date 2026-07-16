import { Link } from 'react-router-dom'
import { useEffect, useState } from 'react'
import {
  FAVORITES_CHANGED_EVENT,
  loadFavorites,
} from '../lib/cafe-favorites'
import { IconStar } from './Icons'

const FAV_ROUTE = 'favorites'

type Props = {
  /** Which header icon is the current page */
  active?: 'fav' | null
}

/**
 * Cafe family header trailing: 즐겨찾기 only.
 * Cart lives in the bottom GNB tab.
 */
export function CafeHeaderActions({ active = null }: Props) {
  const [favTotal, setFavTotal] = useState(() => loadFavorites().length)

  useEffect(() => {
    const sync = () => setFavTotal(loadFavorites().length)
    sync()
    const onVis = () => {
      if (document.visibilityState === 'visible') sync()
    }
    window.addEventListener(FAVORITES_CHANGED_EVENT, sync)
    window.addEventListener('storage', sync)
    window.addEventListener('focus', sync)
    document.addEventListener('visibilitychange', onVis)
    return () => {
      window.removeEventListener(FAVORITES_CHANGED_EVENT, sync)
      window.removeEventListener('storage', sync)
      window.removeEventListener('focus', sync)
      document.removeEventListener('visibilitychange', onVis)
    }
  }, [])

  return (
    <Link
      to={`/cafe/${FAV_ROUTE}`}
      className={`page-header-icon-btn${
        active === 'fav' ? ' is-active is-fav' : ''
      }${favTotal > 0 && active !== 'fav' ? ' has-badge is-fav' : ''}`}
      aria-label={favTotal > 0 ? `즐겨찾기 ${favTotal}개` : '즐겨찾기'}
      aria-current={active === 'fav' ? 'page' : undefined}
    >
      <IconStar size={20} filled={active === 'fav' || favTotal > 0} />
      {favTotal > 0 ? (
        <span className="page-header-icon-badge is-fav" aria-hidden>
          {favTotal > 99 ? '99+' : favTotal}
        </span>
      ) : null}
    </Link>
  )
}
