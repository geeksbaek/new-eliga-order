import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import {
  composeOrder,
  fetchPaymentReasons,
  placeOrder,
} from '../api/eliga'
import { Empty, ErrorBox, Loading } from '../components/UiState'
import { PageHeader } from '../components/PageHeader'
import { formatWon } from '../lib/format'
import { lineTotal } from '../lib/cart-math'
import {
  assertOrderConfirmed,
  pickDefaultPaymentReasonId,
} from '../lib/order-payload'
import { useShop } from '../hooks/useShop'
import type { PaymentReason } from '../lib/types'

export function OrderConfirmPage() {
  const {
    cart,
    cartLoading,
    cartTotal,
    selectedShop,
    selectedShopId,
    canOrder,
    refreshCart,
    getCafeHours,
    isSelectedCafeOpen,
  } = useShop()
  const navigate = useNavigate()
  const hours =
    selectedShopId != null ? getCafeHours(selectedShopId) : null
  const hoursBlockOrder = hours != null && !hours.orderable

  const [reasons, setReasons] = useState<PaymentReason[]>([])
  const [reasonId, setReasonId] = useState<number | null>(null)
  const [confirmed, setConfirmed] = useState(false)
  const [loadingReasons, setLoadingReasons] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [resultMsg, setResultMsg] = useState<string | null>(null)

  useEffect(() => {
    if (!canOrder || selectedShopId == null) {
      setLoadingReasons(false)
      return
    }
    let cancelled = false
    setLoadingReasons(true)
    fetchPaymentReasons(selectedShopId)
      .then((list) => {
        if (cancelled) return
        setReasons(list)
        setReasonId(pickDefaultPaymentReasonId(list))
      })
      .catch((e) => {
        if (!cancelled) {
          setError(
            e instanceof Error ? e.message : '결제 사유를 불러오지 못했습니다',
          )
        }
      })
      .finally(() => {
        if (!cancelled) setLoadingReasons(false)
      })
    return () => {
      cancelled = true
    }
  }, [selectedShopId, canOrder])

  if (!canOrder) {
    return (
      <div className="order-confirm">
        <PageHeader
          back={{ fallbackTo: '/cart', label: '장바구니' }}
          title="주문 확인"
        />
        <Empty>
          카페 매장에서만 주문할 수 있습니다. <Link to="/">매장 선택</Link>
        </Empty>
      </div>
    )
  }

  if (hoursBlockOrder && hours) {
    return (
      <div className="order-confirm">
        <PageHeader
          back={{ fallbackTo: '/cart', label: '장바구니' }}
          title="주문 확인"
        />
        <div className="cafe-hours-banner is-closed" role="status">
          {hours.message}
        </div>
        <Empty>
          운영시간에만 주문할 수 있습니다.{' '}
          <Link to="/cart">장바구니로</Link>
        </Empty>
      </div>
    )
  }

  if (cartLoading || loadingReasons) {
    return <Loading label="주문 정보 준비 중…" />
  }

  if (!cart.items.length || !cart.cartId) {
    return (
      <div className="order-confirm">
        <PageHeader
          back={{ fallbackTo: '/cart', label: '장바구니' }}
          title="주문 확인"
        />
        <Empty>
          장바구니가 비어 있습니다. <Link to="/cart">장바구니</Link>
        </Empty>
      </div>
    )
  }

  async function onSubmit() {
    setError(null)
    setResultMsg(null)
    if (!isSelectedCafeOpen) {
      const h =
        selectedShopId != null ? getCafeHours(selectedShopId) : null
      setError(h?.message ?? '지금은 주문할 수 없습니다')
      return
    }
    try {
      assertOrderConfirmed(confirmed)
    } catch (e) {
      setError(e instanceof Error ? e.message : '확인이 필요합니다')
      return
    }
    if (!cart.cartId || reasonId == null || selectedShopId == null) {
      setError('결제 사유와 장바구니 정보가 필요합니다')
      return
    }

    setBusy(true)
    try {
      const payload = composeOrder({
        shopId: selectedShopId,
        cartId: cart.cartId,
        paymentReasonId: reasonId,
        items: cart.items,
      })
      const res = await placeOrder(payload)
      const orderId =
        res &&
        typeof res === 'object' &&
        'content' in res &&
        (res as { content?: { id?: number; orderId?: number } }).content
          ? (res as { content: { id?: number; orderId?: number } }).content.id ??
            (res as { content: { orderId?: number } }).content.orderId
          : null
      setResultMsg(
        orderId
          ? `주문이 접수되었습니다. 주문번호 ${orderId}`
          : '주문이 접수되었습니다.',
      )
      await refreshCart({ force: true })
      setTimeout(() => {
        navigate(orderId ? `/orders?highlight=${orderId}` : '/orders')
      }, 800)
    } catch (e) {
      setError(e instanceof Error ? e.message : '주문에 실패했습니다')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="order-confirm">
      <PageHeader
        back={{ fallbackTo: '/cart', label: '장바구니' }}
        title="주문 확인"
        sub="아래 내역과 금액을 확인한 뒤, 체크하고 주문하세요. 확인 없이는 주문이 실행되지 않습니다."
      />

      {error && <ErrorBox>{error}</ErrorBox>}
      {resultMsg && <div className="info-box">{resultMsg}</div>}

      <div className="two-col">
        <section className="card card-pad">
          <h2 className="section-title" style={{ marginTop: 0 }}>
            {selectedShop?.name}
          </h2>
          <ul className="confirm-list">
            {cart.items.map((item) => (
              <li key={item.cartItemId}>
                <span>
                  {item.name}
                  {item.options.length > 0 && (
                    <span className="muted">
                      {' '}
                      (
                      {item.options
                        .map((o) => o.value)
                        .join(', ')}
                      )
                    </span>
                  )}
                  <br />
                  <span className="muted">× {item.qty}</span>
                </span>
                <strong>{formatWon(lineTotal(item))}</strong>
              </li>
            ))}
          </ul>
          <div className="cart-total-box" style={{ marginTop: 8, padding: 0, border: 0, boxShadow: 'none' }}>
            <span>총 금액</span>
            <span>{formatWon(cartTotal)}</span>
          </div>
        </section>

        <section className="card card-pad sticky-panel">
          <h2 className="section-title" style={{ marginTop: 0 }}>
            결제 사유
          </h2>
          {reasons.length === 0 ? (
            <p className="muted">선택 가능한 결제 사유가 없습니다.</p>
          ) : (
            <div className="stack">
              {reasons.map((r) => (
                <label key={r.id} className={`option-choice${reasonId === r.id ? ' selected' : ''}`}>
                  <input
                    type="radio"
                    name="paymentReason"
                    checked={reasonId === r.id}
                    onChange={() => setReasonId(r.id)}
                  />
                  <span className="grow">{r.reason}</span>
                </label>
              ))}
            </div>
          )}

          {hoursBlockOrder && hours && (
            <div className="cafe-hours-banner is-closed" role="status">
              {hours.message}
            </div>
          )}

          <label className="confirm-check">
            <input
              type="checkbox"
              checked={confirmed}
              onChange={(e) => setConfirmed(e.target.checked)}
              disabled={hoursBlockOrder}
            />
            <span>
              위 주문 내역과 총 금액 <strong>{formatWon(cartTotal)}</strong>을
              확인했으며, 픽업 주문을 진행합니다.
            </span>
          </label>

          <button
            type="button"
            className="btn btn-primary btn-block"
            disabled={
              busy ||
              !confirmed ||
              reasonId == null ||
              hoursBlockOrder ||
              !isSelectedCafeOpen
            }
            onClick={() => void onSubmit()}
          >
            {hoursBlockOrder
              ? '운영시간 외 · 주문 불가'
              : busy
                ? '주문 중…'
                : '주문하기'}
          </button>
        </section>
      </div>
    </div>
  )
}
