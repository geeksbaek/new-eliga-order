import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import {
  fetchCafeCategories,
  fetchCafeMenu,
  fetchPopularOrders,
  fetchRecentOrders,
} from '../api/eliga'
import { Empty, ErrorBox, Loading } from '../components/UiState'
import { formatDateTime, formatWon } from '../lib/format'
import { useShop } from '../hooks/useShop'
import type { CafeCategory, CafeMenuItem, CafeQuickItem } from '../lib/types'

export function CafeMenuPage() {
  const { shopId: shopIdParam } = useParams()
  const shopId = Number(shopIdParam)
  const navigate = useNavigate()
  const { selectShop, shops } = useShop()
  const shopName = shops.find((s) => s.shopId === shopId)?.name ?? `매장 ${shopId}`

  const [categories, setCategories] = useState<CafeCategory[]>([])
  const [activeCat, setActiveCat] = useState<number | 'all'>('all')
  const [menus, setMenus] = useState<CafeMenuItem[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [recent, setRecent] = useState<CafeQuickItem[]>([])
  const [popular, setPopular] = useState<CafeQuickItem[]>([])
  const [quickError, setQuickError] = useState<string | null>(null)
  const [tab, setTab] = useState<'menu' | 'quick'>('menu')

  useEffect(() => {
    if (Number.isFinite(shopId)) selectShop(shopId)
  }, [shopId, selectShop])

  // Categories once per shop
  useEffect(() => {
    if (!Number.isFinite(shopId)) return
    let cancelled = false
    fetchCafeCategories(shopId)
      .then((cats) => {
        if (!cancelled) setCategories(cats.filter((c) => c.mobileUseYn))
      })
      .catch(() => {
        if (!cancelled) setCategories([])
      })
    return () => {
      cancelled = true
    }
  }, [shopId])

  // Menu when shop or category changes (single fetch — no race)
  useEffect(() => {
    if (!Number.isFinite(shopId)) return
    let cancelled = false
    setLoading(true)
    setError(null)
    const catId = activeCat === 'all' ? undefined : activeCat
    fetchCafeMenu(shopId, catId)
      .then((items) => {
        if (!cancelled) setMenus(items)
      })
      .catch((e) => {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : '메뉴를 불러오지 못했습니다')
          setMenus([])
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [shopId, activeCat])

  useEffect(() => {
    if (!Number.isFinite(shopId)) return
    let cancelled = false
    setQuickError(null)
    Promise.all([fetchRecentOrders(shopId), fetchPopularOrders(shopId)])
      .then(([r, p]) => {
        if (cancelled) return
        setRecent(r)
        setPopular(p)
      })
      .catch((e) => {
        if (cancelled) return
        setRecent([])
        setPopular([])
        setQuickError(
          e instanceof Error ? e.message : '최근·인기 메뉴를 불러오지 못했습니다',
        )
      })
    return () => {
      cancelled = true
    }
  }, [shopId])

  const availableCount = useMemo(
    () => menus.filter((m) => !m.soldOut).length,
    [menus],
  )

  if (!Number.isFinite(shopId)) {
    return <Empty>잘못된 매장입니다. <Link to="/">매장 목록</Link></Empty>
  }

  return (
    <div>
      <div className="row" style={{ marginBottom: 8 }}>
        <Link to="/" className="btn btn-ghost btn-sm">
          ← 매장
        </Link>
      </div>
      <h1 className="page-title">{shopName}</h1>
      <p className="page-sub">
        메뉴를 눌러 옵션을 고르고 담으세요. 품절 메뉴는 주문할 수 없습니다.
      </p>

      <div className="tabs" role="tablist">
        <button
          type="button"
          className={`tab${tab === 'menu' ? ' active' : ''}`}
          onClick={() => setTab('menu')}
        >
          메뉴
        </button>
        <button
          type="button"
          className={`tab${tab === 'quick' ? ' active' : ''}`}
          onClick={() => setTab('quick')}
        >
          최근·인기
        </button>
      </div>

      {tab === 'quick' && (
        <div className="stack">
          {quickError && <ErrorBox>{quickError}</ErrorBox>}
          <section className="card card-pad">
            <h2 className="section-title" style={{ marginTop: 0 }}>
              최근 주문
            </h2>
            <p className="muted" style={{ marginTop: 0, fontSize: '0.88rem' }}>
              이 매장에서 최근에 주문한 메뉴입니다. 탭하면 상세로 이동합니다.
            </p>
            <QuickOrders
              items={recent}
              empty="최근 주문 메뉴가 없습니다."
              onPick={(item) =>
                navigate(`/cafe/${shopId}/menu?d=${item.displayId}`)
              }
              mode="recent"
            />
          </section>
          <section className="card card-pad">
            <h2 className="section-title" style={{ marginTop: 0 }}>
              인기 메뉴
            </h2>
            <p className="muted" style={{ marginTop: 0, fontSize: '0.88rem' }}>
              이 매장에서 자주 찾는 메뉴입니다.
            </p>
            <QuickOrders
              items={popular}
              empty="인기 메뉴가 없습니다."
              onPick={(item) =>
                navigate(`/cafe/${shopId}/menu?d=${item.displayId}`)
              }
              mode="popular"
            />
          </section>
        </div>
      )}

      {tab === 'menu' && (
        <>
          <div className="chip-row" role="tablist" aria-label="카테고리">
            <button
              type="button"
              className={`chip${activeCat === 'all' ? ' active' : ''}`}
              onClick={() => setActiveCat('all')}
            >
              전체
            </button>
            {categories.map((c) => (
              <button
                key={c.id}
                type="button"
                className={`chip${activeCat === c.id ? ' active' : ''}`}
                onClick={() => setActiveCat(c.id)}
              >
                {c.name}
              </button>
            ))}
          </div>

          {loading && <Loading label="메뉴 불러오는 중…" />}
          {error && <ErrorBox>{error}</ErrorBox>}
          {!loading && !error && menus.length === 0 && (
            <Empty>이 카테고리에 메뉴가 없습니다.</Empty>
          )}
          {!loading && menus.length > 0 && (
            <p
              className="muted"
              style={{ marginTop: 0, marginBottom: 10, fontSize: '0.88rem' }}
            >
              {menus.length}개 중 주문 가능 {availableCount}개
            </p>
          )}

          <div className="menu-list">
            {menus.map((item) => (
              <button
                key={item.displayId}
                type="button"
                className={`card menu-item${item.soldOut ? ' soldout' : ''}`}
                disabled={item.soldOut}
                onClick={() => {
                  if (!item.soldOut) {
                    navigate(`/cafe/${shopId}/menu?d=${item.displayId}`)
                  }
                }}
              >
                <div className="menu-body">
                  <div className="row" style={{ gap: 6, marginBottom: 4 }}>
                    {item.label && (
                      <span className="badge badge-label">{item.label}</span>
                    )}
                    {item.soldOut && (
                      <span className="badge badge-soldout">품절</span>
                    )}
                  </div>
                  <p className="menu-name">{item.name}</p>
                  {item.description && (
                    <p className="menu-desc">{item.description}</p>
                  )}
                  <div className="menu-price">{formatWon(item.price)}</div>
                </div>
                <div className="menu-side">
                  <span className="muted" style={{ fontSize: '0.8rem' }}>
                    {item.displayName || item.category}
                  </span>
                  {!item.soldOut && (
                    <span className="btn btn-primary btn-sm">담기</span>
                  )}
                </div>
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  )
}

function QuickOrders({
  items,
  empty,
  onPick,
  mode,
}: {
  items: CafeQuickItem[]
  empty: string
  onPick: (item: CafeQuickItem) => void
  mode: 'recent' | 'popular'
}) {
  if (!items.length) {
    return <p className="muted">{empty}</p>
  }
  return (
    <div className="quick-list">
      {items.map((item) => (
        <button
          key={`${mode}-${item.displayId}-${item.goodsId}`}
          type="button"
          className={`quick-item${item.soldOut ? ' soldout' : ''}`}
          disabled={item.soldOut || !item.displayId}
          onClick={() => onPick(item)}
        >
          <div className="quick-thumb">
            {item.thumbnailUrl ? (
              <img src={item.thumbnailUrl} alt="" loading="lazy" />
            ) : (
              <div className="meal-thumb-empty" aria-hidden>
                ·
              </div>
            )}
          </div>
          <div className="quick-body">
            <p className="quick-name">{item.name || '메뉴'}</p>
            <p className="muted quick-meta">
              {mode === 'recent' && item.lastOrderAt
                ? formatDateTime(item.lastOrderAt)
                : mode === 'popular' && item.orderCountHint
                  ? `${item.orderCountHint}잔`
                  : item.qty > 1
                    ? `${item.qty}개`
                    : '바로 담기'}
              {item.soldOut ? ' · 품절' : ''}
            </p>
          </div>
          <span className="quick-chevron" aria-hidden>
            ›
          </span>
        </button>
      ))}
    </div>
  )
}
