import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { addToCart, fetchCafeMenuDetail } from '../api/eliga'
import { Empty, ErrorBox, Loading } from '../components/UiState'
import { ImagePreview, type PreviewImage } from '../components/ImagePreview'
import { PageHeader } from '../components/PageHeader'
import { formatWon, formatKcal } from '../lib/format'
import { sampleImageEdgeColor } from '../lib/image-edge-color'
import { MenuThumb } from '../components/MenuThumb'
import { IconStar } from '../components/Icons'
import { unitPriceWithOptions } from '../lib/cart-math'
import {
  defaultSelections,
  isExclusiveMultiGroup,
  selectionsToOptions,
} from '../lib/menu-options'
import { isFavorite, toggleFavorite } from '../lib/cafe-favorites'
import { soldOutBlocksOrder } from '../lib/shop-rules'
import { useShop } from '../hooks/useShop'
import type { GoodsOption, GoodsVariant, MenuDetail, SelectedOption } from '../lib/types'

export function MenuDetailPage() {
  const { shopId: shopIdParam } = useParams()
  const [searchParams] = useSearchParams()
  const shopId = Number(shopIdParam)
  const displayId = Number(searchParams.get('d') || searchParams.get('displayId'))
  const navigate = useNavigate()
  const { refreshCart, selectShop, getCafeHours } = useShop()

  const [detail, setDetail] = useState<MenuDetail | null>(null)
  const [variantId, setVariantId] = useState<number | null>(null)
  const [selected, setSelected] = useState<Record<number, number[]>>({})
  const [qty, setQty] = useState(1)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [toast, setToast] = useState<string | null>(null)
  const [preview, setPreview] = useState<PreviewImage | null>(null)
  /** Letterbox fill sampled from image edges (fallback white). */
  const [heroPadColor, setHeroPadColor] = useState('#ffffff')
  const [favOn, setFavOn] = useState(
    () =>
      Number.isFinite(displayId) &&
      displayId > 0 &&
      Number.isFinite(shopId) &&
      isFavorite(displayId, shopId),
  )

  useEffect(() => {
    if (Number.isFinite(shopId)) selectShop(shopId)
  }, [shopId, selectShop])

  useEffect(() => {
    if (!Number.isFinite(displayId) || displayId <= 0 || !Number.isFinite(shopId)) {
      setFavOn(false)
      return
    }
    setFavOn(isFavorite(displayId, shopId))
  }, [displayId, shopId])

  useEffect(() => {
    if (!Number.isFinite(displayId) || displayId <= 0) {
      setLoading(false)
      return
    }
    let cancelled = false
    setLoading(true)
    setError(null)
    setQty(1)
    fetchCafeMenuDetail(displayId)
      .then((d) => {
        if (cancelled) return
        setDetail(d)
        const firstAvail =
          d.variants.find((v) => !v.soldOut) ?? d.variants[0] ?? null
        setVariantId(firstAvail?.goodsId ?? null)
        if (firstAvail) {
          setSelected(defaultSelections(firstAvail))
        } else {
          setSelected({})
        }
      })
      .catch((e) => {
        if (!cancelled) {
          setError(
            e instanceof Error ? e.message : '메뉴 상세를 불러오지 못했습니다',
          )
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

  const heroImage =
    variant?.thumbnailUrl || detail?.thumbnailUrl || null

  useEffect(() => {
    let cancelled = false
    setHeroPadColor('#ffffff')
    if (!heroImage) return
    void sampleImageEdgeColor(heroImage).then((color) => {
      if (!cancelled) setHeroPadColor(color)
    })
    return () => {
      cancelled = true
    }
  }, [heroImage])

  const titleName =
    variant?.name?.replace(/\s*(HOT|ICED|ICE)\s*$/i, '') ||
    detail?.variants[0]?.name ||
    '메뉴'

  const selectedOptions: SelectedOption[] = useMemo(() => {
    if (!variant) return []
    return selectionsToOptions(variant, selected)
  }, [selected, variant])

  const unitPrice = variant
    ? unitPriceWithOptions(variant.price, variant.options, selectedOptions)
    : 0
  const line = unitPrice * qty
  const hours = getCafeHours(shopId)
  const hoursBlocked = !hours.orderable
  const blocked =
    !variant || soldOutBlocksOrder(variant.soldOut) || hoursBlocked

  const missingRequired = useMemo(() => {
    if (!variant) return [] as string[]
    const missing: string[] = []
    for (const opt of variant.options) {
      // Single-select groups are required (cup, topping, etc.)
      if (!opt.multiSelect) {
        const picks = selected[opt.optionId] ?? []
        if (!picks.length) missing.push(opt.name)
      }
    }
    return missing
  }, [variant, selected])

  function toggleOption(opt: GoodsOption, menuId: number) {
    setSelected((prev) => {
      const cur = prev[opt.optionId] ?? []
      if (opt.multiSelect) {
        // Optional multi: toggle. Mutually exclusive pairs (연하게 vs 샷추가) —
        // keep multi API flag but only one at a time when both are "intensity" choices
        const exclusive = isExclusiveMultiGroup(opt)
        if (exclusive) {
          if (cur.includes(menuId)) {
            return { ...prev, [opt.optionId]: [] }
          }
          return { ...prev, [opt.optionId]: [menuId] }
        }
        const has = cur.includes(menuId)
        return {
          ...prev,
          [opt.optionId]: has
            ? cur.filter((id) => id !== menuId)
            : [...cur, menuId],
        }
      }
      // Single-select: always exactly one (required)
      return { ...prev, [opt.optionId]: [menuId] }
    })
  }

  async function onAdd() {
    if (!variant || blocked) return
    if (hoursBlocked) {
      setError(hours.message)
      return
    }
    if (missingRequired.length) {
      setError(`필수 옵션을 선택해 주세요: ${missingRequired.join(', ')}`)
      return
    }
    setBusy(true)
    setError(null)
    setToast(null)
    try {
      await addToCart({
        shopId,
        goodsId: variant.goodsId,
        qty,
        options: selectedOptions,
      })
      await refreshCart({ force: true, shopId })
      setToast('장바구니에 담았습니다')
      setTimeout(() => {
        if (window.history.length > 1) navigate(-1)
        else navigate(`/cafe/${shopId}`)
      }, 350)
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

  const labelU = (detail.label || '').toUpperCase()
  const labelTagClass =
    labelU === 'BEST'
      ? 'tag tag-best'
      : labelU === 'NEW'
        ? 'tag tag-new'
        : detail.label
          ? 'tag tag-hot'
          : ''

  return (
    <div className="menu-detail">
      <PageHeader
        back={{ fallbackTo: `/cafe/${shopId}`, label: '메뉴' }}
        title={
          <span className="detail-title-row">
            {detail.label ? (
              <span className={labelTagClass}>{detail.label}</span>
            ) : null}
            <span className="detail-title-name">{titleName}</span>
          </span>
        }
        sub={
          [
            variant?.description?.trim(),
            variant?.calorie != null ? formatKcal(variant.calorie) : null,
          ]
            .filter(Boolean)
            .join(' · ') || undefined
        }
        trailing={
          <button
            type="button"
            className={`menu-fav-btn detail-fav-btn${favOn ? ' is-on' : ''}`}
            aria-label={favOn ? '즐겨찾기 해제' : '즐겨찾기'}
            aria-pressed={favOn}
            onClick={() => {
              const next = toggleFavorite(displayId, shopId)
              setFavOn(isFavorite(displayId, shopId, next))
            }}
          >
            <IconStar size={20} filled={favOn} />
          </button>
        }
      />

      <button
        type="button"
        className={`detail-hero${!heroImage ? ' is-empty' : ''}`}
        style={
          heroImage
            ? { backgroundColor: heroPadColor }
            : undefined
        }
        aria-label={`${titleName} 사진 크게 보기`}
        onClick={() =>
          setPreview({
            src: heroImage,
            alt: titleName,
            caption: titleName,
          })
        }
      >
        <MenuThumb
          src={heroImage}
          alt=""
          width={480}
          height={320}
          loading="eager"
          variant="block"
        />
      </button>

      {hoursBlocked && (
        <div className="cafe-hours-banner is-closed" role="status">
          {hours.message}
        </div>
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
                  setError(null)
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
        variant.options.map((opt) => {
          const exclusive = isExclusiveMultiGroup(opt)
          return (
            <div key={opt.optionId} className="option-group">
              <h3>
                {opt.name}
                {!opt.multiSelect || exclusive ? ' (택 1)' : ' (선택)'}
              </h3>
              <div className="option-choices" role="group" aria-label={opt.name}>
                {opt.menus.map((menu) => {
                  const isOn = (selected[opt.optionId] ?? []).includes(
                    menu.menuId,
                  )
                  return (
                    <button
                      key={menu.menuId}
                      type="button"
                      className={`option-choice${isOn ? ' selected' : ''}`}
                      aria-pressed={isOn}
                      onClick={() => toggleOption(opt, menu.menuId)}
                    >
                      <span className="grow">{menu.name}</span>
                      {menu.price > 0 ? (
                        <span className="option-choice-price">
                          +{formatWon(menu.price)}
                        </span>
                      ) : null}
                    </button>
                  )
                })}
              </div>
            </div>
          )
        })}

      <div className="card card-pad detail-checkout">
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
          disabled={blocked || busy || missingRequired.length > 0}
          onClick={() => void onAdd()}
        >
          {hoursBlocked
            ? hours.statusLabel.includes('마감') || hours.reason === 'closed'
              ? '운영시간 외 · 담기 불가'
              : hours.statusLabel
            : blocked && soldOutBlocksOrder(variant?.soldOut)
              ? '품절된 메뉴입니다'
              : missingRequired.length
                ? '옵션을 선택해 주세요'
                : busy
                  ? '담는 중…'
                  : '장바구니에 담기'}
        </button>
      </div>

      <ImagePreview image={preview} onClose={() => setPreview(null)} />
    </div>
  )
}


