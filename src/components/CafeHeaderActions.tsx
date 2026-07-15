import { Link } from 'react-router-dom'
import { useEffect, useState } from 'react'
import { loadFavorites } from '../lib/cafe-favorites'
import { useShop } from '../hooks/useShop'
import { IconBag, IconStar } from './Icons'

const FAV_ROUTE = 'favorites'

type Props = {
  /** Which header icon is the current page */
  active?: 'fav' | 'cart' | null
}

/**
 * Shared cafe header trailing: 즐겨찾기 + 장바구니 icons with badges.
 * Used on cafe menu, favorites, and cart so chrome stays consistent.
 */
export function CafeHeaderActions({ active = null }: Props) {
  const { cartCountAll } = useShop()
  const [favTotal, setFavTotal] = useState(() => loadFavorites().length)

  useEffect(() => {
    setFavTotal(loadFavorites().length)
    const sync = () => setFavTotal(loadFavorites().length)
    const onVis = () => {
      if (document.visibilityState === 'visible') sync()
    }
    window.addEventListener('focus', sync)
    document.addEventListener('visibilitychange', onVis)
    return () => {
      window.removeEventListener('focus', sync)
      document.removeEventListener('visibilitychange', onVis)
    }
  }, [])

  return (
    <>
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
      <Link
        to="/cart"
        className={`page-header-icon-btn${
          active === 'cart' ? ' is-active is-cart' : ''
        }${cartCountAll > 0 ? ' has-badge is-cart' : ''}`}
        aria-label={
          cartCountAll > 0 ? `장바구니 ${cartCountAll}개` : '장바구니'
        }
        aria-current={active === 'cart' ? 'page' : undefined}
      >
        <IconBag size={20} />
        {cartCountAll > 0 ? (
          <span className="page-header-icon-badge is-cart" aria-hidden>
            {cartCountAll > 99 ? '99+' : cartCountAll}
          </span>
        ) : null}
      </Link>
    </>
  )
}
