import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { useShop } from '../hooks/useShop'
import { formatWon } from '../lib/format'
import { canOrderFromShop } from '../lib/shop-rules'

export function Layout() {
  const { logout } = useAuth()
  const { cartCount, cartTotal, selectedShop, canOrder } = useShop()
  const navigate = useNavigate()
  const location = useLocation()

  const hideCartBar =
    location.pathname.startsWith('/cart') ||
    location.pathname.startsWith('/order') ||
    location.pathname.startsWith('/login')

  const showSticky =
    !hideCartBar && canOrder && cartCount > 0 && canOrderFromShop(selectedShop)

  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="app-header-inner">
          <NavLink to="/" className="brand" aria-label="홈">
            <span className="brand-mark">E</span>
            <span>new 엘리가</span>
          </NavLink>
          <div className="header-spacer" />
          <nav className="header-nav" aria-label="주요 메뉴">
            <NavLink
              to="/"
              end
              className={({ isActive }) =>
                `nav-link${isActive ? ' active' : ''}`
              }
            >
              매장
            </NavLink>
            <NavLink
              to="/orders"
              className={({ isActive }) =>
                `nav-link${isActive ? ' active' : ''}`
              }
            >
              내역
            </NavLink>
            <NavLink
              to="/cart"
              className={({ isActive }) =>
                `nav-link${isActive ? ' active' : ''}`
              }
            >
              장바구니
              {cartCount > 0 ? ` (${cartCount})` : ''}
            </NavLink>
            <button
              type="button"
              className="nav-link"
              onClick={() => {
                logout()
                navigate('/login', { replace: true })
              }}
            >
              로그아웃
            </button>
          </nav>
        </div>
      </header>

      <main className={`app-main${showSticky ? '' : ' no-cart-pad'}`}>
        <Outlet />
      </main>

      {showSticky && (
        <div className="sticky-cart">
          <div className="sticky-cart-inner">
            <div className="cart-summary">
              <strong>{formatWon(cartTotal)}</strong>
              <span>
                {selectedShop?.name ?? '카페'} · {cartCount}개
              </span>
            </div>
            <button
              type="button"
              className="btn btn-primary"
              onClick={() => navigate('/cart')}
            >
              장바구니 보기
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
