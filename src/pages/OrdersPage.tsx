import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import {
  fetchOrderHistory,
  fetchOrderStatus,
  fetchRecentOrders,
} from '../api/eliga'
import { Empty, ErrorBox, Loading } from '../components/UiState'
import {
  formatDateTime,
  formatWon,
  orderStatusLabel,
} from '../lib/format'
import { useShop } from '../hooks/useShop'
import type { OrderHistoryView } from '../lib/types'

export function OrdersPage() {
  const { selectedShopId, shops, canOrder } = useShop()
  const [params] = useSearchParams()
  const highlight = params.get('highlight')

  const [tab, setTab] = useState<'history' | 'recent' | 'status'>('history')
  const [history, setHistory] = useState<OrderHistoryView[]>([])
  const [recent, setRecent] = useState<OrderHistoryView[]>([])
  const [statusId, setStatusId] = useState(highlight ?? '')
  const [status, setStatus] = useState<unknown>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const cafeShopId =
    selectedShopId && canOrder
      ? selectedShopId
      : shops.find((s) => s.type === 'CAFE')?.shopId

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setError(null)
    ;(async () => {
      try {
        // History is account-wide; shop filter optional
        const h = await fetchOrderHistory(undefined)
        if (!cancelled) setHistory(h)
        if (cafeShopId != null) {
          // recent endpoint returns menu shortcuts — map to a compact history-like view below
          const r = await fetchRecentOrders(cafeShopId)
          if (!cancelled) {
            setRecent(
              r.map((item, i) => ({
                orderId: item.displayId || i,
                orderNo: item.displayId ? String(item.displayId) : '',
                shopId: cafeShopId,
                shopName: shops.find((s) => s.shopId === cafeShopId)?.name ?? '',
                shopType: 'CAFE',
                status: item.soldOut ? '품절' : '최근 메뉴',
                orderedAt: item.lastOrderAt ?? '',
                totalPaid: 0,
                items: [
                  {
                    name: item.name,
                    qty: item.qty,
                    price: 0,
                    options: [],
                  },
                ],
              })),
            )
          }
        } else if (!cancelled) {
          setRecent([])
        }
      } catch (e) {
        if (!cancelled) {
          setError(
            e instanceof Error ? e.message : '주문 내역을 불러오지 못했습니다',
          )
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [cafeShopId, shops])

  async function loadStatus() {
    if (!statusId.trim()) return
    setError(null)
    try {
      const s = await fetchOrderStatus(statusId.trim())
      setStatus(s)
      setTab('status')
    } catch (e) {
      setError(e instanceof Error ? e.message : '상태 조회 실패')
    }
  }

  return (
    <div>
      <h1 className="page-title">주문 내역</h1>
      <p className="page-sub">최근 3개월 주문과 상태를 확인합니다.</p>

      <div className="tabs">
        <button
          type="button"
          className={`tab${tab === 'history' ? ' active' : ''}`}
          onClick={() => setTab('history')}
        >
          전체
        </button>
        <button
          type="button"
          className={`tab${tab === 'recent' ? ' active' : ''}`}
          onClick={() => setTab('recent')}
        >
          최근 메뉴
        </button>
        <button
          type="button"
          className={`tab${tab === 'status' ? ' active' : ''}`}
          onClick={() => setTab('status')}
        >
          상태
        </button>
      </div>

      {error && <ErrorBox>{error}</ErrorBox>}
      {loading && <Loading />}

      {tab === 'status' && (
        <div className="card card-pad stack">
          <div className="field">
            <label htmlFor="orderId">주문 번호</label>
            <input
              id="orderId"
              value={statusId}
              onChange={(e) => setStatusId(e.target.value)}
              placeholder="주문 ID"
            />
          </div>
          <button
            type="button"
            className="btn btn-accent"
            onClick={() => void loadStatus()}
          >
            조회
          </button>
          {status != null && (
            <pre className="order-json">{JSON.stringify(status, null, 2)}</pre>
          )}
        </div>
      )}

      {tab === 'history' && !loading && (
        <OrderList
          data={history}
          empty="주문 내역이 없습니다."
          highlightId={highlight}
        />
      )}
      {tab === 'recent' && !loading && (
        <OrderList data={recent} empty="최근 메뉴가 없습니다." compact />
      )}

      <p style={{ marginTop: 18 }}>
        <Link to="/" className="btn btn-ghost btn-sm">
          매장으로
        </Link>
      </p>
    </div>
  )
}

function OrderList({
  data,
  empty,
  highlightId,
  compact,
}: {
  data: OrderHistoryView[]
  empty: string
  highlightId?: string | null
  compact?: boolean
}) {
  if (!data.length) return <Empty>{empty}</Empty>
  return (
    <div className="stack">
      {data.map((row) => {
        const active =
          highlightId != null && String(row.orderId) === String(highlightId)
        return (
          <article
            key={`${row.orderId}-${row.orderNo}-${row.orderedAt}`}
            className={`card card-pad${active ? ' order-highlight' : ''}`}
          >
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <div>
                <strong className="order-id">
                  {compact
                    ? row.items[0]?.name || '메뉴'
                    : row.orderNo
                      ? `#${row.orderNo}`
                      : `#${row.orderId}`}
                </strong>
                {row.shopName && (
                  <p className="muted order-shop">{row.shopName}</p>
                )}
              </div>
              {row.status && (
                <span className="badge badge-cafe">
                  {orderStatusLabel(row.status) === row.status
                    ? row.status
                    : orderStatusLabel(row.status)}
                </span>
              )}
            </div>
            {row.orderedAt && (
              <p className="muted order-when">{formatDateTime(row.orderedAt)}</p>
            )}
            <ul className="confirm-list order-lines">
              {row.items.slice(0, 6).map((it, i) => (
                <li key={i}>
                  <span>
                    {it.name}
                    {it.options.length > 0 && (
                      <span className="muted"> ({it.options.join(', ')})</span>
                    )}
                    <span className="muted"> × {it.qty}</span>
                  </span>
                  {!compact && it.price > 0 && (
                    <strong>{formatWon(it.price)}</strong>
                  )}
                </li>
              ))}
            </ul>
            {!compact && row.totalPaid > 0 && (
              <div className="order-total">
                <span>결제 금액</span>
                <strong>{formatWon(row.totalPaid)}</strong>
              </div>
            )}
          </article>
        )
      })}
    </div>
  )
}
