import { Navigate, Route, Routes, useLocation } from 'react-router-dom'
import { AuthProvider, useAuth } from './hooks/useAuth'
import { ShopProvider } from './hooks/useShop'
import { Layout } from './components/Layout'
import { Loading } from './components/UiState'
import { LoginPage } from './pages/LoginPage'
import { ShopsPage } from './pages/ShopsPage'
import { DiningMenuPage } from './pages/DiningMenuPage'
import { CafeMenuPage } from './pages/CafeMenuPage'
import { MenuDetailPage } from './pages/MenuDetailPage'
import { CartPage } from './pages/CartPage'
import { OrderConfirmPage } from './pages/OrderConfirmPage'
import { OrdersPage } from './pages/OrdersPage'

function RequireAuth({ children }: { children: React.ReactNode }) {
  const { ready, authed } = useAuth()
  const location = useLocation()
  if (!ready) return <Loading label="준비 중…" />
  if (!authed) {
    return <Navigate to="/login" replace state={{ from: location.pathname }} />
  }
  return <>{children}</>
}

function AppRoutes() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        element={
          <RequireAuth>
            <ShopProvider>
              <Layout />
            </ShopProvider>
          </RequireAuth>
        }
      >
        <Route index element={<ShopsPage />} />
        <Route path="dining/:shopId" element={<DiningMenuPage />} />
        <Route path="cafe/:shopId" element={<CafeMenuPage />} />
        {/* displayId is a query (?d=) so LIFT can serve /cafe/:id/menu/index.html */}
        <Route path="cafe/:shopId/menu" element={<MenuDetailPage />} />
        <Route path="cart" element={<CartPage />} />
        <Route path="order/confirm" element={<OrderConfirmPage />} />
        <Route path="orders" element={<OrdersPage />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}

export default function App() {
  return (
    <AuthProvider>
      <AppRoutes />
    </AuthProvider>
  )
}
