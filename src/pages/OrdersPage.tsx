import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import {
  fetchOrderHistory,
  fetchOrderStatus,
  fetchRecentOrders,
} from '../api/eliga'
import { Empty, ErrorBox, Loading } from '../components/UiState'
import { orderStatusLabel } from '../lib/format'
import { useShop } from '../hooks/useShop'

export function OrdersPage() {
  const { selectedShopId, shops, canOrder } = useShop()
  const [params] = useSearchParams()
  const highlight = params.get('highlight')

  const [tab, setTab] = useState<'history' | 'recent' | 'status'>('history')
  const [history, setHistory] = useState<unknown>(null)
  const [recent, setRecent] = useState<unknown>(null)
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
        const h = await fetchOrderHistory(cafeShopId)
        if (!cancelled) setHistory(h)
        if (cafeShopId != null) {
          const r = await fetchRecentOrders(cafeShopId)
          if (!cancelled) setRecent(r)
        }
      } catch (e) {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : '주문 내역을 불러오지 못했습니다')
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [cafeShopId])

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
      <p className="page-sub">최근 주문과 상태를 확인합니다.</p>

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
          최근
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
          <button type="button" className="btn btn-accent" onClick={() => void loadStatus()}>
            조회
          </button>
          {status != null && <OrderBlob data={status} />}
        </div>
      )}

      {tab === 'history' && !loading && (
        <OrderList data={history} empty="주문 내역이 없습니다." />
      )}
      {tab === 'recent' && !loading && (
        <OrderList data={recent} empty="최근 주문이 없습니다." />
      )}

      <p style={{ marginTop: 18 }}>
        <Link to="/" className="btn btn-ghost btn-sm">
          매장으로
        </Link>
      </p>
    </div>
  )
}

function OrderList({ data, empty }: { data: unknown; empty: string }) {
  const list = extractList(data)
  if (!list.length) return <Empty>{empty}</Empty>
  return (
    <div className="stack">
      {list.map((row, i) => {
        const r = row as Record<string, unknown>
        const id = r.id ?? r.orderId ?? i
        const status = String(r.orderStatus ?? r.status ?? '')
        const shop = r.shopName ? String(r.shopName) : ''
        const when = String(r.createdAt ?? r.orderDate ?? r.regDate ?? '')
        return (
          <article key={String(id)} className="card card-pad">
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <strong>#{String(id)}</strong>
              {status && (
                <span className="badge badge-cafe">{orderStatusLabel(status)}</span>
              )}
            </div>
            {shop && <p className="muted" style={{ margin: '6px 0 0' }}>{shop}</p>}
            {when && <p className="muted" style={{ margin: '4px 0 0', fontSize: '0.85rem' }}>{when}</p>}
            <OrderBlob data={r} compact />
          </article>
        )
      })}
    </div>
  )
}

function OrderBlob({ data, compact }: { data: unknown; compact?: boolean }) {
  if (data == null) return null
  if (compact) {
    const r = data as Record<string, unknown>
    const items = r.orderItems ?? r.items ?? r.goodsOrderItems
    if (Array.isArray(items) && items.length) {
      return (
        <ul className="confirm-list" style={{ marginTop: 8 }}>
          {items.slice(0, 5).map((it, i) => {
            const item = it as Record<string, unknown>
            const name = String(
              item.goodsName ?? item.name ?? item.displayName ?? `항목 ${i + 1}`,
            )
            const qty = item.goodsQty ?? item.qty ?? item.quantity
            return (
              <li key={i}>
                <span>{name}</span>
                <span className="muted">{qty != null ? `×${qty}` : ''}</span>
              </li>
            )
          })}
        </ul>
      )
    }
    return null
  }
  return (
    <pre
      style={{
        margin: 0,
        whiteSpace: 'pre-wrap',
        wordBreak: 'break-word',
        fontSize: '0.8rem',
        background: 'var(--surface-2)',
        padding: 12,
        borderRadius: 10,
        overflow: 'auto',
      }}
    >
      {JSON.stringify(data, null, 2)}
    </pre>
  )
}

function extractList(data: unknown): unknown[] {
  if (data == null) return []
  if (Array.isArray(data)) return data
  if (typeof data === 'object' && data !== null) {
    const o = data as Record<string, unknown>
    if (Array.isArray(o.content)) return o.content
    if (o.content && typeof o.content === 'object') {
      const c = o.content as Record<string, unknown>
      if (Array.isArray(c.orders)) return c.orders
      if (Array.isArray(c.list)) return c.list
    }
    if (Array.isArray(o.orders)) return o.orders
  }
  return []
}
