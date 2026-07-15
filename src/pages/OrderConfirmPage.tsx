import { useEffect, useRef, useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import {
  composeOrder,
  fetchPaymentReasons,
  placeOrder,
  restoreStashedCart,
} from '../api/eliga'
import { Empty, ErrorBox, Loading } from '../components/UiState'
import { PageHeader } from '../components/PageHeader'
import { formatWon } from '../lib/format'
import { lineTotal } from '../lib/cart-math'
import {
  assertOrderConfirmed,
  pickDefaultPaymentReasonId,
} from '../lib/order-payload'
import {
  assertQuickOrderCartIsolated,
  clearQuickOrderSession,
  loadQuickOrderSession,
  type QuickOrderSession,
} from '../lib/quick-order'
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
    selectShop,
    setCartLocal,
  } = useShop()
  const navigate = useNavigate()
  const location = useLocation()
  const hours =
    selectedShopId != null ? getCafeHours(selectedShopId) : null
  const hoursBlockOrder = hours != null && !hours.orderable

  const [quickSession] = useState<QuickOrderSession | null>(() =>
    loadQuickOrderSession(),
  )
  const isQuickOrder =
    Boolean(
      (location.state as { quickOrder?: boolean } | null)?.quickOrder,
    ) || quickSession != null

  const [reasons, setReasons] = useState<PaymentReason[]>([])
  const [reasonId, setReasonId] = useState<number | null>(null)
  const [confirmed, setConfirmed] = useState(false)
  const [loadingReasons, setLoadingReasons] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [resultMsg, setResultMsg] = useState<string | null>(null)
  const [isolationError, setIsolationError] = useState<string | null>(null)

  /** Set true only after a successful placeOrder so we skip stash restore. */
  const orderedOkRef = useRef(false)
  const restoringRef = useRef(false)

  // Align selected shop with quick-order session
  useEffect(() => {
    if (quickSession?.shopId != null) {
      selectShop(quickSession.shopId)
    }
  }, [quickSession?.shopId, selectShop])

  // Hard isolation check for quick order
  useEffect(() => {
    if (!isQuickOrder || !quickSession) {
      setIsolationError(null)
      return
    }
    if (cartLoading) return
    if (selectedShopId !== quickSession.shopId) return
    try {
      assertQuickOrderCartIsolated(cart, {
        goodsId: quickSession.expectedGoodsId,
        qty: quickSession.expectedQty,
      })
      setIsolationError(null)
    } catch (e) {
      setIsolationError(
        e instanceof Error
          ? e.message
          : '바로 주문 장바구니 격리에 실패했습니다',
      )
    }
  }, [
    isQuickOrder,
    quickSession,
    cart,
    cartLoading,
    selectedShopId,
  ])

  // Restore stashed cart if user leaves without completing order.
  // Deferred + pathname check avoids React Strict Mode double-mount false restore.
  useEffect(() => {
    return () => {
      if (orderedOkRef.current) return
      const session = loadQuickOrderSession()
      if (!session) return
      window.setTimeout(() => {
        if (orderedOkRef.current) return
        if (restoringRef.current) return
        // Still on confirm (Strict Mode remount) — leave session alone
        if (window.location.pathname.includes('/order/confirm')) return
        const latest = loadQuickOrderSession()
        if (!latest) return
        restoringRef.current = true
        void (async () => {
          try {
            const restored = await restoreStashedCart(
              latest.shopId,
              latest.stashed,
            )
            setCartLocal(restored, latest.shopId)
          } catch {
            await refreshCart({
              silent: true,
              shopId: latest.shopId,
              force: true,
            })
          } finally {
            clearQuickOrderSession()
          }
        })()
      }, 0)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- unmount-only restore
  }, [])

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
          back={{
            fallbackTo: isQuickOrder ? '/' : '/cart',
            label: isQuickOrder ? '홈' : '장바구니',
          }}
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
          back={{
            fallbackTo: isQuickOrder ? '/' : '/cart',
            label: isQuickOrder ? '홈' : '장바구니',
          }}
          title="주문 확인"
        />
        <div className="cafe-hours-banner is-closed" role="status">
          {hours.message}
        </div>
        <Empty>
          운영시간에만 주문할 수 있습니다.{' '}
          <Link to={isQuickOrder ? '/' : '/cart'}>
            {isQuickOrder ? '홈으로' : '장바구니로'}
          </Link>
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
          back={{
            fallbackTo: isQuickOrder ? '/' : '/cart',
            label: isQuickOrder ? '홈' : '장바구니',
          }}
          title="주문 확인"
        />
        <Empty>
          장바구니가 비어 있습니다.{' '}
          <Link to={isQuickOrder ? '/' : '/cart'}>
            {isQuickOrder ? '홈' : '장바구니'}
          </Link>
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

    // Final hard gate: never co-pay stashed / foreign lines
    if (isQuickOrder && quickSession) {
      try {
        assertQuickOrderCartIsolated(cart, {
          goodsId: quickSession.expectedGoodsId,
          qty: quickSession.expectedQty,
        })
      } catch (e) {
        setError(
          e instanceof Error
            ? e.message
            : '바로 주문 격리 검증에 실패했습니다',
        )
        return
      }
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
      orderedOkRef.current = true
      clearQuickOrderSession()
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

  const blockSubmit =
    busy ||
    !confirmed ||
    reasonId == null ||
    hoursBlockOrder ||
    !isSelectedCafeOpen ||
    isolationError != null

  return (
    <div className="order-confirm">
      <PageHeader
        back={{
          fallbackTo: isQuickOrder
            ? selectedShopId != null
              ? `/cafe/${selectedShopId}`
              : '/'
            : '/cart',
          label: isQuickOrder ? '메뉴' : '장바구니',
        }}
        title={isQuickOrder ? '바로 주문 확인' : '주문 확인'}
        sub={
          isQuickOrder
            ? '이 메뉴 1잔만 결제합니다. 기존 장바구니 항목은 포함되지 않습니다.'
            : '아래 내역과 금액을 확인한 뒤, 체크하고 주문하세요. 확인 없이는 주문이 실행되지 않습니다.'
        }
      />

      {isQuickOrder && (
        <div className="info-box quick-order-banner" role="status">
          바로 주문 · {quickSession?.menuName || cart.items[0]?.name || '1잔'}{' '}
          만 결제
          {quickSession && quickSession.stashed.length > 0
            ? ` · 이전 장바구니 ${quickSession.stashed.length}건은 결제 후가 아니라 취소 시에만 복구`
            : ''}
        </div>
      )}

      {(error || isolationError) && (
        <ErrorBox>{error || isolationError}</ErrorBox>
      )}
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
              disabled={hoursBlockOrder || isolationError != null}
            />
            <span>
              위 주문 내역과 총 금액 <strong>{formatWon(cartTotal)}</strong>을
              확인했으며, 픽업 주문을 진행합니다.
              {isQuickOrder ? ' (바로 주문 1잔만)' : ''}
            </span>
          </label>

          <button
            type="button"
            className="btn btn-primary btn-block"
            disabled={blockSubmit}
            onClick={() => void onSubmit()}
          >
            {hoursBlockOrder
              ? '운영시간 외 · 주문 불가'
              : isolationError
                ? '바로 주문 검증 실패'
                : busy
                  ? '주문 중…'
                  : isQuickOrder
                    ? '1잔 주문하기'
                    : '주문하기'}
          </button>
        </section>
      </div>
    </div>
  )
}
