import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import {
  fetchCafeCategories,
  fetchCafeMenu,
  fetchPopularOrders,
  fetchRecentOrders,
} from '../api/eliga'
import { Empty, ErrorBox, Loading } from '../components/UiState'
import { formatWon } from '../lib/format'
import { useShop } from '../hooks/useShop'
import type { CafeCategory, CafeMenuItem } from '../lib/types'

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
  const [recent, setRecent] = useState<unknown>(null)
  const [popular, setPopular] = useState<unknown>(null)
  const [tab, setTab] = useState<'menu' | 'quick'>('menu')

  useEffect(() => {
    if (Number.isFinite(shopId)) selectShop(shopId)
  }, [shopId, selectShop])

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setError(null)
    ;(async () => {
      try {
        const cats = await fetchCafeCategories(shopId)
        if (cancelled) return
        const mobileCats = cats.filter((c) => c.mobileUseYn)
        setCategories(mobileCats)
        const catId = activeCat === 'all' ? undefined : activeCat
        const items = await fetchCafeMenu(shopId, catId)
        if (!cancelled) setMenus(items)
      } catch (e) {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : '메뉴를 불러오지 못했습니다')
          setMenus([])
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- reload when cat changes via separate effect below for all
  }, [shopId])

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    const catId = activeCat === 'all' ? undefined : activeCat
    fetchCafeMenu(shopId, catId)
      .then((items) => {
        if (!cancelled) setMenus(items)
      })
      .catch((e) => {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : '메뉴를 불러오지 못했습니다')
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
    fetchRecentOrders(shopId)
      .then(setRecent)
      .catch(() => setRecent(null))
    fetchPopularOrders(shopId)
      .then(setPopular)
      .catch(() => setPopular(null))
  }, [shopId])

  const availableCount = useMemo(
    () => menus.filter((m) => !m.soldOut).length,
    [menus],
  )

  return (
    <div>
      <div className="row" style={{ marginBottom: 8 }}>
        <Link to="/" className="btn btn-ghost btn-sm">
          ← 매장
        </Link>
      </div>
      <h1 className="page-title">{shopName}</h1>
      <p className="page-sub">메뉴를 눌러 옵션을 고르고 담으세요. 품절 메뉴는 주문할 수 없습니다.</p>

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
          <section className="card card-pad">
            <h2 className="section-title" style={{ marginTop: 0 }}>
              최근 주문
            </h2>
            <QuickOrders data={recent} />
          </section>
          <section className="card card-pad">
            <h2 className="section-title" style={{ marginTop: 0 }}>
              인기 메뉴
            </h2>
            <QuickOrders data={popular} />
          </section>
          <p className="muted" style={{ fontSize: '0.88rem' }}>
            빠른 재주문은 메뉴 탭에서 해당 상품을 선택해 옵션을 확인한 뒤 담아 주세요.
          </p>
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
            <p className="muted" style={{ marginTop: 0, marginBottom: 10, fontSize: '0.88rem' }}>
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

function QuickOrders({ data }: { data: unknown }) {
  if (data == null) {
    return <p className="muted">불러올 수 없거나 내역이 없습니다.</p>
  }
  const content =
    data && typeof data === 'object' && 'content' in data
      ? (data as { content: unknown }).content
      : data
  const list = Array.isArray(content) ? content : content ? [content] : []
  if (!list.length) {
    return <p className="muted">표시할 항목이 없습니다.</p>
  }
  return (
    <ul className="confirm-list">
      {list.slice(0, 8).map((row, i) => {
        const r = row as Record<string, unknown>
        let name = JSON.stringify(r).slice(0, 80)
        if (typeof r.name === 'string' && r.name) name = r.name
        else if (r.goodsName != null) name = String(r.goodsName)
        else if (r.displayName != null) name = String(r.displayName)
        return (
          <li key={i}>
            <span>{name}</span>
            <span className="muted">
              {r.orderCount != null ? `${r.orderCount}회` : ''}
            </span>
          </li>
        )
      })}
    </ul>
  )
}
