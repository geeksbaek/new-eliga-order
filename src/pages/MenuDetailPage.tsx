import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { addToCart, fetchCafeMenuDetail } from '../api/eliga'
import { Empty, ErrorBox, Loading } from '../components/UiState'
import { formatWon, formatKcal } from '../lib/format'
import { unitPriceWithOptions } from '../lib/cart-math'
import { soldOutBlocksOrder } from '../lib/shop-rules'
import { useShop } from '../hooks/useShop'
import type { GoodsVariant, MenuDetail, SelectedOption } from '../lib/types'

export function MenuDetailPage() {
  const { shopId: shopIdParam } = useParams()
  const [searchParams] = useSearchParams()
  const shopId = Number(shopIdParam)
  const displayId = Number(searchParams.get('d') || searchParams.get('displayId'))
  const navigate = useNavigate()
  const { refreshCart, selectShop } = useShop()

  const [detail, setDetail] = useState<MenuDetail | null>(null)
  const [variantId, setVariantId] = useState<number | null>(null)
  const [selected, setSelected] = useState<Record<number, number[]>>({})
  const [qty, setQty] = useState(1)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [toast, setToast] = useState<string | null>(null)

  useEffect(() => {
    if (Number.isFinite(shopId)) selectShop(shopId)
  }, [shopId, selectShop])

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setError(null)
    fetchCafeMenuDetail(displayId)
      .then((d) => {
        if (cancelled) return
        setDetail(d)
        const firstAvail =
          d.variants.find((v) => !v.soldOut) ?? d.variants[0] ?? null
        setVariantId(firstAvail?.goodsId ?? null)
        if (firstAvail) {
          setSelected(defaultSelections(firstAvail))
        }
      })
      .catch((e) => {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : '메뉴 상세를 불러오지 못했습니다')
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [displayId])

  const variant: GoodsVariant | null =
    detail?.variants.find((v) => v.goodsId === variantId) ?? null

  const selectedOptions: SelectedOption[] = useMemo(() => {
    return Object.entries(selected).flatMap(([optionId, menuIds]) => {
      if (!menuIds.length) return []
      return [{ optionId: Number(optionId), menuIds }]
    })
  }, [selected])

  const unitPrice = variant
    ? unitPriceWithOptions(variant.price, variant.options, selectedOptions)
    : 0
  const line = unitPrice * qty
  const blocked = !variant || soldOutBlocksOrder(variant.soldOut)

  function toggleOption(optionId: number, menuId: number, multi: boolean) {
    setSelected((prev) => {
      const cur = prev[optionId] ?? []
      if (multi) {
        const has = cur.includes(menuId)
        return {
          ...prev,
          [optionId]: has ? cur.filter((id) => id !== menuId) : [...cur, menuId],
        }
      }
      return { ...prev, [optionId]: [menuId] }
    })
  }

  async function onAdd() {
    if (!variant || blocked) return
    setBusy(true)
    setToast(null)
    try {
      await addToCart({
        shopId,
        goodsId: variant.goodsId,
        qty,
        options: selectedOptions,
      })
      await refreshCart()
      setToast('장바구니에 담았습니다')
      setTimeout(() => navigate(`/cafe/${shopId}`), 450)
    } catch (e) {
      setError(e instanceof Error ? e.message : '담기에 실패했습니다')
    } finally {
      setBusy(false)
    }
  }

  if (!Number.isFinite(displayId) || displayId <= 0) {
    return (
      <Empty>
        메뉴를 선택해 주세요.{' '}
        <Link to={`/cafe/${shopId}`}>메뉴 목록</Link>
      </Empty>
    )
  }
  if (loading) return <Loading label="메뉴 상세 불러오는 중…" />
  if (error && !detail) return <ErrorBox>{error}</ErrorBox>
  if (!detail || !detail.variants.length) {
    return <Empty>메뉴 정보를 찾을 수 없습니다.</Empty>
  }

  return (
    <div>
      <div className="row" style={{ marginBottom: 8 }}>
        <Link to={`/cafe/${shopId}`} className="btn btn-ghost btn-sm">
          ← 메뉴
        </Link>
      </div>

      <h1 className="page-title">
        {variant?.name?.replace(/\s*(HOT|ICED|ICE)\s*$/i, '') ||
          detail.variants[0]?.name ||
          '메뉴'}
      </h1>
      {detail.label && (
        <div className="shop-meta" style={{ marginBottom: 12 }}>
          <span className="badge badge-label">{detail.label}</span>
        </div>
      )}
      {variant?.description && (
        <p className="page-sub">{variant.description}</p>
      )}
      {variant?.calorie != null && (
        <p className="muted" style={{ marginTop: -8 }}>
          {formatKcal(variant.calorie)}
        </p>
      )}

      {error && (
        <div style={{ marginBottom: 12 }}>
          <ErrorBox>{error}</ErrorBox>
        </div>
      )}
      {toast && (
        <div className="info-box" style={{ marginBottom: 12 }}>
          {toast}
        </div>
      )}

      {detail.variants.length > 1 && (
        <>
          <h2 className="section-title">온도 / 종류</h2>
          <div className="variant-row">
            {detail.variants.map((v) => (
              <button
                key={v.goodsId}
                type="button"
                className={`variant-btn${variantId === v.goodsId ? ' active' : ''}`}
                disabled={v.soldOut}
                onClick={() => {
                  setVariantId(v.goodsId)
                  setSelected(defaultSelections(v))
                }}
              >
                {v.displayName || v.name}
                {v.soldOut ? ' (품절)' : ''}
              </button>
            ))}
          </div>
        </>
      )}

      {variant &&
        variant.options.map((opt) => (
          <div key={opt.optionId} className="option-group">
            <h3>
              {opt.name}
              {opt.multiSelect ? ' (복수 선택)' : ''}
            </h3>
            <div className="option-choices">
              {opt.menus.map((menu) => {
                const isOn = (selected[opt.optionId] ?? []).includes(menu.menuId)
                return (
                  <button
                    key={menu.menuId}
                    type="button"
                    className={`option-choice${isOn ? ' selected' : ''}`}
                    onClick={() =>
                      toggleOption(opt.optionId, menu.menuId, opt.multiSelect)
                    }
                  >
                    <span className="grow">{menu.name}</span>
                    <span>
                      {menu.price > 0 ? `+${formatWon(menu.price)}` : '포함'}
                    </span>
                  </button>
                )
              })}
            </div>
          </div>
        ))}

      <div className="card card-pad" style={{ marginTop: 8 }}>
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <span className="muted">수량</span>
          <div className="qty-control">
            <button
              type="button"
              className="icon-btn"
              aria-label="수량 감소"
              disabled={qty <= 1}
              onClick={() => setQty((q) => Math.max(1, q - 1))}
            >
              −
            </button>
            <span>{qty}</span>
            <button
              type="button"
              className="icon-btn"
              aria-label="수량 증가"
              onClick={() => setQty((q) => q + 1)}
            >
              +
            </button>
          </div>
        </div>
        <div
          className="row"
          style={{ justifyContent: 'space-between', marginTop: 14 }}
        >
          <span className="muted">합계</span>
          <strong style={{ fontSize: '1.2rem' }}>{formatWon(line)}</strong>
        </div>
        <button
          type="button"
          className="btn btn-primary btn-block"
          style={{ marginTop: 16 }}
          disabled={blocked || busy}
          onClick={() => void onAdd()}
        >
          {blocked ? '품절된 메뉴입니다' : busy ? '담는 중…' : '장바구니에 담기'}
        </button>
      </div>
    </div>
  )
}

function defaultSelections(variant: GoodsVariant): Record<number, number[]> {
  const out: Record<number, number[]> = {}
  for (const opt of variant.options) {
    if (!opt.multiSelect && opt.menus[0]) {
      out[opt.optionId] = [opt.menus[0].menuId]
    } else {
      out[opt.optionId] = []
    }
  }
  return out
}
