import { useNavigate } from 'react-router-dom'
import { useShop } from '../hooks/useShop'
import { Empty, ErrorBox, Loading } from '../components/UiState'
import { isCafeShop, isCafeteriaShop } from '../lib/shop-rules'

export function ShopsPage() {
  const {
    shops,
    shopsLoading,
    shopsError,
    selectedShopId,
    selectShop,
    refreshShops,
  } = useShop()
  const navigate = useNavigate()

  function openShop(shopId: number, type: string) {
    selectShop(shopId)
    if (isCafeteriaShop(type) || shopId === 7) {
      navigate(`/dining/${shopId}`)
    } else {
      navigate(`/cafe/${shopId}`)
    }
  }

  return (
    <div>
      <h1 className="page-title">매장 선택</h1>
      <p className="page-sub">
        식당은 식단 조회만, 카페는 담기·주문까지 가능합니다. 마지막으로 쓴 매장을 기억합니다.
      </p>

      {shopsError && (
        <div className="stack" style={{ marginBottom: 12 }}>
          <ErrorBox>{shopsError}</ErrorBox>
          <button type="button" className="btn btn-ghost" onClick={() => void refreshShops()}>
            다시 시도
          </button>
        </div>
      )}

      {shopsLoading && <Loading label="매장 불러오는 중…" />}

      {!shopsLoading && !shopsError && shops.length === 0 && (
        <Empty>표시할 매장이 없습니다. 로그인 상태와 권한을 확인해 주세요.</Empty>
      )}

      <div className="shop-grid">
        {shops.map((shop) => {
          const cafe = isCafeShop(shop.type)
          const cafeteria = isCafeteriaShop(shop.type) || shop.shopId === 7
          return (
            <button
              key={shop.shopId}
              type="button"
              className="card shop-card"
              onClick={() => openShop(shop.shopId, shop.type)}
              aria-current={selectedShopId === shop.shopId ? 'true' : undefined}
            >
              <p className="shop-name">{shop.name}</p>
              <div className="shop-meta">
                {cafeteria && <span className="badge badge-cafeteria">식당 · 조회만</span>}
                {cafe && <span className="badge badge-cafe">카페 · 주문 가능</span>}
                {shop.open ? (
                  <span className="badge badge-open">영업 중</span>
                ) : (
                  <span className="badge badge-closed">영업 종료</span>
                )}
                {selectedShopId === shop.shopId && (
                  <span className="badge">최근 선택</span>
                )}
              </div>
            </button>
          )
        })}
      </div>
    </div>
  )
}
