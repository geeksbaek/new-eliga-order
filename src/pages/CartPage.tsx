import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { deleteCartItems, updateCartQuantity } from '../api/eliga'
import { Empty, ErrorBox, Loading } from '../components/UiState'
import { formatWon } from '../lib/format'
import { lineTotal } from '../lib/cart-math'
import { useShop } from '../hooks/useShop'

export function CartPage() {
  const {
    cart,
    cartLoading,
    cartTotal,
    cartCount,
    selectedShop,
    selectedShopId,
    canOrder,
    refreshCart,
  } = useShop()
  const navigate = useNavigate()
  const [error, setError] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<number | null>(null)

  if (!canOrder) {
    return (
      <div>
        <h1 className="page-title">장바구니</h1>
        <Empty>
          식당 매장은 장바구니를 지원하지 않습니다.{' '}
          <Link to="/">카페 매장</Link>을 선택해 주세요.
        </Empty>
      </div>
    )
  }

  async function changeQty(cartItemId: number, goodsQty: number) {
    if (!cart.cartId) return
    setBusyId(cartItemId)
    setError(null)
    try {
      if (goodsQty <= 0) {
        await deleteCartItems({
          cartId: cart.cartId,
          cartItemIds: [cartItemId],
        })
      } else {
        await updateCartQuantity({
          cartId: cart.cartId,
          cartItemId,
          goodsQty,
        })
      }
      await refreshCart()
    } catch (e) {
      setError(e instanceof Error ? e.message : '수량 변경 실패')
    } finally {
      setBusyId(null)
    }
  }

  async function removeItem(cartItemId: number) {
    if (!cart.cartId) return
    setBusyId(cartItemId)
    setError(null)
    try {
      await deleteCartItems({
        cartId: cart.cartId,
        cartItemIds: [cartItemId],
      })
      await refreshCart()
    } catch (e) {
      setError(e instanceof Error ? e.message : '삭제 실패')
    } finally {
      setBusyId(null)
    }
  }

  return (
    <div>
      <h1 className="page-title">장바구니</h1>
      <p className="page-sub">
        {selectedShop?.name ?? '카페'}
        {cartCount > 0 ? ` · ${cartCount}개` : ''}
      </p>

      {error && <ErrorBox>{error}</ErrorBox>}
      {cartLoading && <Loading label="장바구니 불러오는 중…" />}

      {!cartLoading && cart.items.length === 0 && (
        <Empty>
          장바구니가 비어 있습니다.{' '}
          {selectedShopId != null && (
            <Link to={`/cafe/${selectedShopId}`}>메뉴 보러 가기</Link>
          )}
        </Empty>
      )}

      <div className="stack">
        {cart.items.map((item) => (
          <article key={item.cartItemId} className="card cart-line">
            <div className="cart-line-top">
              <div>
                <p className="cart-line-name">{item.name}</p>
                {item.options.length > 0 && (
                  <p className="cart-line-opts">
                    {item.options.map((o) => `${o.option}: ${o.value}`).join(' · ')}
                  </p>
                )}
              </div>
              <strong>{formatWon(lineTotal(item))}</strong>
            </div>
            <div className="cart-line-bottom">
              <div className="qty-control">
                <button
                  type="button"
                  className="icon-btn"
                  aria-label="수량 감소"
                  disabled={busyId === item.cartItemId}
                  onClick={() => void changeQty(item.cartItemId, item.qty - 1)}
                >
                  −
                </button>
                <span>{item.qty}</span>
                <button
                  type="button"
                  className="icon-btn"
                  aria-label="수량 증가"
                  disabled={busyId === item.cartItemId}
                  onClick={() => void changeQty(item.cartItemId, item.qty + 1)}
                >
                  +
                </button>
              </div>
              <button
                type="button"
                className="btn btn-danger btn-sm"
                disabled={busyId === item.cartItemId}
                onClick={() => void removeItem(item.cartItemId)}
              >
                삭제
              </button>
            </div>
          </article>
        ))}
      </div>

      {cart.items.length > 0 && (
        <>
          <div className="card cart-total-box" style={{ marginTop: 14 }}>
            <span>총 금액</span>
            <span>{formatWon(cartTotal)}</span>
          </div>
          <button
            type="button"
            className="btn btn-primary btn-block"
            style={{ marginTop: 12 }}
            onClick={() => navigate('/order/confirm')}
          >
            주문 확인으로
          </button>
          {selectedShopId != null && (
            <Link
              to={`/cafe/${selectedShopId}`}
              className="btn btn-ghost btn-block"
              style={{ marginTop: 8 }}
            >
              메뉴 더 담기
            </Link>
          )}
        </>
      )}
    </div>
  )
}
