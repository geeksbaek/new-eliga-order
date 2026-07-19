import { useMemo } from 'react'
import { useLocation } from 'react-router-dom'
import { CafeMenuPage } from './CafeMenuPage'
import { MenuDetailPage } from './MenuDetailPage'

/**
 * Keep the cafe list mounted while menu detail is open so sticky shop/category
 * chips do not remount (and flash) on swipe-back / history POP.
 *
 * Routes: /cafe/:shopId and /cafe/:shopId/menu both render this shell.
 */
export function CafeShopShell() {
  const { pathname } = useLocation()
  const isDetail = useMemo(
    () => /\/cafe\/[^/]+\/menu\/?$/.test(pathname),
    [pathname],
  )

  return (
    <>
      <div
        className="cafe-list-layer"
        hidden={isDetail}
        aria-hidden={isDetail}
        {...(isDetail ? ({ inert: '' } as object) : null)}
      >
        <CafeMenuPage listActive={!isDetail} />
      </div>
      {isDetail ? <MenuDetailPage /> : null}
    </>
  )
}
