import { useEffect, useMemo, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Empty, ErrorBox } from '../components/UiState'
import { CafeHeaderActions } from '../components/CafeHeaderActions'
import { PageHeader } from '../components/PageHeader'
import { MenuThumb } from '../components/MenuThumb'
import { IconChevronRight, IconCup, IconTrash } from '../components/Icons'
import { formatWon } from '../lib/format'
import { lineTotal } from '../lib/cart-math'
import { ensureHorizontalVisible } from '../lib/scroll-chip'
import { listCafeShops } from '../lib/shop-rules'
import { useCartMutations } from '../hooks/useCartMutations'
import { useShop } from '../hooks/useShop'

const CART_SKEL = 3

export function CartPage() {
  const {
    cart,
    cartLoading,
    cartTotal,
    cartCount,
    cartCountByShop,
    cartCountAll,
    selectedShop,
    selectedShopId,
    selectShop,
    shops,
    canOrder,
    getCafeHours,
    isSelectedCafeOpen,
  } = useShop()
  const navigate = useNavigate()
  const [error, setError] = useState<string | null>(null)
  const pillRefs = useRef(new Map<number, HTMLButtonElement>())

  const cafeShops = useMemo(() => listCafeShops(shops), [shops])

  const { changeLineQty, removeLine } = useCartMutations({
    onError: (err) => {
      setError(
        err.error instanceof Error
          ? err.error.message
          : '장바구니 반영에 실패했습니다',
      )
    },
  })

  // Ensure a cafe is selected when landing on cart
  useEffect(() => {
    if (selectedShopId != null) return
    if (cafeShops[0]) selectShop(cafeShops[0].shopId)
  }, [selectedShopId, cafeShops, selectShop])

  useEffect(() => {
    if (selectedShopId == null) return
    const id = requestAnimationFrame(() => {
      ensureHorizontalVisible(pillRefs.current.get(selectedShopId))
    })
    return () => cancelAnimationFrame(id)
  }, [selectedShopId, cafeShops.length])

  const otherShopCounts = useMemo(() => {
    if (selectedShopId == null) return []
    return cafeShops
      .filter((s) => s.shopId !== selectedShopId)
      .map((s) => ({
        shopId: s.shopId,
        name: s.name,
        count: cartCountByShop[s.shopId] ?? 0,
      }))
      .filter((s) => s.count > 0)
  }, [cafeShops, selectedShopId, cartCountByShop])

  const showInitialLoading = cartLoading && cart.items.length === 0
  const hours =
    selectedShopId != null ? getCafeHours(selectedShopId) : null
  const hoursBlockOrder = hours != null && !hours.orderable

  if (!canOrder && selectedShopId != null) {
    return (
      <div className="cart-page cafe">
        <PageHeader
          title="장바구니"
          trailing={<CafeHeaderActions active="cart" />}
        />
        <Empty>
          식당 매장은 장바구니를 지원하지 않습니다.{' '}
          <Link to="/cafe/5">카페 매장</Link>을 선택해 주세요.
        </Empty>
      </div>
    )
  }

  return (
    <div className="cart-page cafe">
      <PageHeader
        title="장바구니"
        sub={
          cartCountAll > 0
            ? `전체 ${cartCountAll}개 · 주문은 매장별로`
            : '매장별로 따로 담깁니다'
        }
        trailing={<CafeHeaderActions active="cart" />}
      />

      {cafeShops.length > 0 && (
        <div
          className="shop-pills shop-pills-scroll cafe-shop-pills cart-shop-pills"
          role="list"
          data-hscroll
        >
          {cafeShops.map((s) => {
            const n = cartCountByShop[s.shopId] ?? 0
            const active = s.shopId === selectedShopId
            return (
              <button
                key={s.shopId}
                type="button"
                role="listitem"
                className={`shop-pill${active ? ' is-active' : ''}`}
                ref={(el) => {
                  if (el) pillRefs.current.set(s.shopId, el)
                  else pillRefs.current.delete(s.shopId)
                }}
                onClick={() => {
                  setError(null)
                  selectShop(s.shopId)
                }}
              >
                {s.name}
                {n > 0 ? (
                  <span className="shop-pill-count" aria-label={`${n}개`}>
                    {n}
                  </span>
                ) : null}
                {(() => {
                  const h = getCafeHours(s.shopId)
                  if (h.reason === 'unknown' || h.orderable) return null
                  return (
                    <span className="shop-pill-closed" aria-label="영업 종료">
                      마감
                    </span>
                  )
                })()}
              </button>
            )
          })}
        </div>
      )}

      {error && <ErrorBox>{error}</ErrorBox>}

      {hoursBlockOrder && hours && (
        <div className="cafe-hours-banner is-closed" role="status">
          {hours.message}
        </div>
      )}

      {otherShopCounts.length > 0 && cart.items.length > 0 && (
        <p className="cart-multi-hint">
          다른 매장 장바구니{' '}
          {otherShopCounts.map((s) => s.count).reduce((a, b) => a + b, 0)}개가
          있습니다. 주문은 지금 선택한 매장만 진행됩니다.
        </p>
      )}

      {showInitialLoading && (
        <div className="cart-line-list" aria-busy>
          {Array.from({ length: CART_SKEL }, (_, i) => (
            <div key={i} className="cart-line is-skel" aria-hidden>
              <div className="cart-line-thumb" />
              <div className="cart-line-main">
                <span className="cafe-skel-line cafe-skel-name" />
                <span className="cafe-skel-line cafe-skel-desc" />
              </div>
              <div className="cart-line-side">
                <span className="cafe-skel-line cafe-skel-price" />
              </div>
            </div>
          ))}
        </div>
      )}

      {!showInitialLoading && cart.items.length === 0 && (
        <div className="cart-empty">
          <p className="cart-empty-title">
            {selectedShop?.name ?? '이 매장'} 장바구니가 비어 있습니다
          </p>
          <p className="cart-empty-desc">
            메뉴를 담은 뒤 여기서 수량을 조절하고 주문할 수 있습니다.
          </p>
          {selectedShopId != null && (
            <Link
              to={`/cafe/${selectedShopId}`}
              className="btn btn-primary cart-empty-cta"
            >
              <IconCup size={18} />
              <span>메뉴 보러 가기</span>
              <IconChevronRight size={18} />
            </Link>
          )}
        </div>
      )}

      {!showInitialLoading && cart.items.length > 0 && (
        <div className="cart-line-list">
          {cart.items.map((item) => (
            <article key={item.cartItemId} className="cart-line">
              <div className="cart-line-thumb" aria-hidden>
                <MenuThumb
                  src={item.thumbnailUrl}
                  width={56}
                  height={56}
                />
              </div>
              <div className="cart-line-main">
                <p className="cart-line-name">{item.name}</p>
                {item.options.length > 0 ? (
                  <p className="cart-line-opts">
                    {item.options
                      .map((o) => `${o.option}: ${o.value}`)
                      .join(' · ')}
                  </p>
                ) : (
                  <p className="cart-line-opts cart-line-unit">
                    {formatWon(item.price)} / 개
                  </p>
                )}
              </div>
              <div className="cart-line-side">
                <strong className="cart-line-total">
                  {formatWon(lineTotal(item))}
                </strong>
                <div className="menu-qty">
                  <button
                    type="button"
                    className="menu-qty-btn"
                    aria-label={`${item.name} 수량 감소`}
                    onClick={() => {
                      setError(null)
                      changeLineQty(item.cartItemId, item.qty - 1)
                    }}
                  >
                    −
                  </button>
                  <span className="menu-qty-val" aria-live="polite">
                    {item.qty}
                  </span>
                  <button
                    type="button"
                    className="menu-qty-btn menu-qty-btn-plus"
                    aria-label={`${item.name} 수량 증가`}
                    disabled={hoursBlockOrder}
                    onClick={() => {
                      if (hoursBlockOrder) {
                        setError(hours?.message ?? '지금은 주문할 수 없습니다')
                        return
                      }
                      setError(null)
                      changeLineQty(item.cartItemId, item.qty + 1)
                    }}
                  >
                    +
                  </button>
                </div>
                <button
                  type="button"
                  className="cart-line-remove"
                  aria-label={`${item.name} 삭제`}
                  onClick={() => {
                    setError(null)
                    void removeLine(item.cartItemId)
                  }}
                >
                  <IconTrash size={16} />
                </button>
              </div>
            </article>
          ))}
        </div>
      )}

      {cart.items.length > 0 && (
        <div className="checkout-bar">
          <div className="checkout-bar-sum">
            <span>
              {selectedShop?.name ? `${selectedShop.name} 합계` : '합계'}
            </span>
            <strong>{formatWon(cartTotal)}</strong>
          </div>
          <p className="checkout-bar-note">
            {hoursBlockOrder
              ? hours?.message ?? '운영시간 외에는 주문할 수 없습니다'
              : `${cartCount}개 · 주문은 이 매장 장바구니만 포함됩니다`}
          </p>
          <button
            type="button"
            className="btn btn-primary btn-block"
            disabled={hoursBlockOrder || !isSelectedCafeOpen}
            onClick={() => {
              if (hoursBlockOrder) {
                setError(hours?.message ?? '지금은 주문할 수 없습니다')
                return
              }
              navigate('/order/confirm')
            }}
          >
            {hoursBlockOrder ? '운영시간 외 · 주문 불가' : '주문하기'}
          </button>
          {selectedShopId != null && (
            <Link
              to={`/cafe/${selectedShopId}`}
              className="btn btn-ghost btn-block cart-more-cta"
            >
              <IconCup size={16} />
              <span>메뉴 더 담기</span>
              <IconChevronRight size={16} />
            </Link>
          )}
        </div>
      )}
    </div>
  )
}
