import { useCallback, useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { fetchDiningMenu, fetchRecentOrders } from '../api/eliga'
import { Empty, ErrorBox } from '../components/UiState'
import { ImagePreview, type PreviewImage } from '../components/ImagePreview'
import { PageHeader } from '../components/PageHeader'
import { IconChevronRight, IconSettings } from '../components/Icons'
import {
  cachePeek,
  cacheSet,
  homeLunchKey,
  homeRecentAllKey,
} from '../lib/query-cache'
import {
  prefetchCafeShop,
  schedulePrefetchCafe,
} from '../lib/prefetch-cafe'
import { useScrollRestore } from '../hooks/useScrollRestore'
import { congestionLabel, formatKcal, todayISODate } from '../lib/format'
import { MenuThumb } from '../components/MenuThumb'
import {
  dishPreviewFromGroup,
  groupDiningDishes,
  pickBestPeriod,
  type GroupedDiningDish,
} from '../lib/dining-group'
import {
  dishMatchesPrefs,
  loadDiningPrefs,
  prefsToSet,
  sortDishesByPref,
} from '../lib/dining-prefs'
import {
  CAFETERIA_SHOP_ID,
  DEFAULT_CAFE_SHOP_ID,
  isCafeShop,
  isCafeteriaShop,
  listCafeShops,
} from '../lib/shop-rules'
import { useAuth } from '../hooks/useAuth'
import { useShop } from '../hooks/useShop'
import type { CafeQuickItem, DiningPeriod } from '../lib/types'

/** Skeleton placeholders while lunch loads (not a fixed card height). */
const LUNCH_SKELETON_ROWS = 3
const RAIL_SLOTS = 4

function congestionClass(type: string | null | undefined): string {
  switch (type) {
    case 'SMOOTH':
      return 'cong-smooth'
    case 'NORMAL':
      return 'cong-normal'
    case 'CROWDED':
      return 'cong-crowded'
    default:
      return ''
  }
}

function LunchDishRow({
  dish,
  recommended,
  onPreview,
}: {
  dish: GroupedDiningDish
  recommended?: boolean
  onPreview: (img: PreviewImage) => void
}) {
  const courseLabel = dish.courseNames.join(' · ')
  const preview = dishPreviewFromGroup(dish, `${courseLabel} · ${dish.name}`)
  return (
    <button
      type="button"
      className={`course-line${dish.soldOut ? ' is-soldout' : ''}${
        recommended ? ' is-recommended' : ''
      }`}
      aria-label={`${dish.name}${recommended ? ' 추천' : ''} 상세 보기`}
      onClick={() => onPreview(preview)}
    >
      <div className="course-line-thumb">
        <MenuThumb src={dish.imageUrl} width={44} height={44} />
      </div>
      <div className="course-line-body">
        <span className="course-line-label" title={courseLabel}>
          {courseLabel}
          {recommended ? (
            <span className="dining-rec-badge">추천</span>
          ) : null}
        </span>
        <p className="course-line-name">
          <span className="course-line-name-text">{dish.name}</span>
          <span className="course-line-kcal">
            {dish.calorie != null ? formatKcal(dish.calorie) : '\u00a0'}
          </span>
        </p>
      </div>
      <span
        className={`pill pill-sm pill-slot course-line-status ${congestionClass(dish.congestion)}`}
      >
        {dish.congestion ? congestionLabel(dish.congestion) : '\u00a0'}
      </span>
    </button>
  )
}

export type HomeRecentItem = CafeQuickItem & {
  shopId: number
  shopName: string
}

function sortRecentByTime(items: HomeRecentItem[]): HomeRecentItem[] {
  return [...items].sort((a, b) => {
    const ta = a.lastOrderAt ? Date.parse(a.lastOrderAt) : 0
    const tb = b.lastOrderAt ? Date.parse(b.lastOrderAt) : 0
    if (tb !== ta) return tb - ta
    return (b.displayId || 0) - (a.displayId || 0)
  })
}

function LunchSkeletonRow() {
  return (
    <div className="course-line is-skel" aria-hidden>
      <div className="course-line-thumb" />
      <div className="course-line-body">
        <span className="home-skel home-skel-label" />
        <span className="home-skel home-skel-name" />
      </div>
      <span className="home-skel home-skel-status" />
    </div>
  )
}

export function ShopsPage() {
  const {
    shops,
    shopsLoading,
    shopsError,
    selectedShopId,
    selectShop,
    refreshShops,
  } = useShop()
  const { userId, logout } = useAuth()
  const navigate = useNavigate()
  useScrollRestore()

  const diningShop =
    shops.find((s) => isCafeteriaShop(s.type) || s.shopId === CAFETERIA_SHOP_ID) ??
    null

  const preferredCafe =
    shops.find((s) => s.shopId === selectedShopId && isCafeShop(s.type)) ??
    shops.find((s) => s.shopId === DEFAULT_CAFE_SHOP_ID) ??
    shops.find((s) => isCafeShop(s.type)) ??
    null

  const cafeShops = useMemo(() => listCafeShops(shops), [shops])

  const lunchShopId = diningShop?.shopId ?? CAFETERIA_SHOP_ID
  const today = todayISODate()

  const [diningPrefs, setDiningPrefs] = useState(() => loadDiningPrefs())
  const diningPrefsSet = useMemo(
    () => prefsToSet(diningPrefs),
    [diningPrefs],
  )

  // Re-read prefs when returning from dining page
  useEffect(() => {
    const sync = () => setDiningPrefs(loadDiningPrefs())
    const onVis = () => {
      if (document.visibilityState === 'visible') sync()
    }
    window.addEventListener('focus', sync)
    document.addEventListener('visibilitychange', onVis)
    return () => {
      window.removeEventListener('focus', sync)
      document.removeEventListener('visibilitychange', onVis)
    }
  }, [])

  const [period, setPeriod] = useState<DiningPeriod | null>(() =>
    cachePeek(homeLunchKey(lunchShopId, today)),
  )
  const [lunchLoading, setLunchLoading] = useState(() => period == null)
  const [recent, setRecent] = useState<HomeRecentItem[]>(
    () => cachePeek(homeRecentAllKey()) ?? [],
  )
  const [railReady, setRailReady] = useState(
    () => cachePeek(homeRecentAllKey()) != null,
  )
  const [preview, setPreview] = useState<PreviewImage | null>(null)
  const closePreview = useCallback(() => setPreview(null), [])

  const shortName = useMemo(() => {
    if (!userId) return ''
    return userId.split('@')[0] || userId
  }, [userId])

  const loadHomeLunch = useCallback(
    async (sid: number, force = false) => {
      const day = todayISODate()
      const key = homeLunchKey(sid, day)
      if (!force) {
        const hit = cachePeek<DiningPeriod>(key)
        if (hit) {
          setPeriod(hit)
          setLunchLoading(false)
          void fetchDiningMenu(sid, day)
            .then((periods) => {
              const best = pickBestPeriod(periods, { dateISO: day })
              if (best) {
                cacheSet(key, best)
                setPeriod(best)
              }
            })
            .catch(() => {})
          return
        }
      }
      setLunchLoading(true)
      try {
        const periods = await fetchDiningMenu(sid, day)
        const best = pickBestPeriod(periods, { dateISO: day })
        if (best) cacheSet(key, best)
        setPeriod(best)
      } catch {
        if (!cachePeek(key)) setPeriod(null)
      } finally {
        setLunchLoading(false)
      }
    },
    [],
  )

  const loadHomeRecentAll = useCallback(
    async (cafes: Array<{ shopId: number; name: string }>, force = false) => {
      const key = homeRecentAllKey()
      if (!force) {
        const hit = cachePeek<HomeRecentItem[]>(key)
        if (hit) {
          setRecent(hit)
          setRailReady(true)
          // background revalidate
          void Promise.all(
            cafes.map(async (s) => {
              try {
                const items = await fetchRecentOrders(s.shopId)
                return items.map((it) => ({
                  ...it,
                  shopId: s.shopId,
                  shopName: s.name,
                }))
              } catch {
                return [] as HomeRecentItem[]
              }
            }),
          ).then((chunks) => {
            const merged = sortRecentByTime(chunks.flat()).slice(0, 12)
            cacheSet(key, merged)
            setRecent(merged)
          })
          return
        }
      }
      setRailReady(false)
      try {
        const chunks = await Promise.all(
          cafes.map(async (s) => {
            try {
              const items = await fetchRecentOrders(s.shopId)
              return items.map((it) => ({
                ...it,
                shopId: s.shopId,
                shopName: s.name,
              }))
            } catch {
              return [] as HomeRecentItem[]
            }
          }),
        )
        const merged = sortRecentByTime(chunks.flat()).slice(0, 12)
        cacheSet(key, merged)
        setRecent(merged)
      } catch {
        setRecent([])
      } finally {
        setRailReady(true)
      }
    },
    [],
  )

  useEffect(() => {
    void loadHomeLunch(lunchShopId)
  }, [lunchShopId, loadHomeLunch])

  useEffect(() => {
    void loadHomeRecentAll(cafeShops)
  }, [cafeShops, loadHomeRecentAll])

  // Prefetch cafe menus while user is still on home (idle).
  useEffect(() => {
    const ids =
      cafeShops.length > 0
        ? cafeShops.map((s) => s.shopId)
        : [preferredCafe?.shopId ?? DEFAULT_CAFE_SHOP_ID]
    for (const id of ids) schedulePrefetchCafe(id)
  }, [cafeShops, preferredCafe?.shopId])

  function goDining() {
    const id = diningShop?.shopId ?? CAFETERIA_SHOP_ID
    selectShop(id)
    navigate(`/dining/${id}`)
  }

  function goCafe(shopId?: number) {
    const id = shopId ?? preferredCafe?.shopId ?? DEFAULT_CAFE_SHOP_ID
    selectShop(id)
    // Kick network before route paint so CafeMenuPage can hit warm cache.
    void prefetchCafeShop(id)
    navigate(`/cafe/${id}`)
  }

  const periodTitle = period?.time || (lunchLoading ? '식단' : '오늘 식단')
  const timeRange = period
    ? `${(period.startTime || '').slice(0, 5)}–${(period.endTime || '').slice(0, 5)} · 춘식도락`
    : lunchLoading
      ? '불러오는 중 · 춘식도락'
      : '식단 없음 · 춘식도락'

  const lunchDishes = useMemo(() => {
    const raw = groupDiningDishes(period?.courses)
    return sortDishesByPref(raw, diningPrefsSet)
  }, [period, diningPrefsSet])
  const showLunchSkeleton = lunchLoading && lunchDishes.length === 0

  return (
    <div className="home">
      <PageHeader
        kicker={todayISODate()}
        title={shortName || '엘리가오더'}
        trailing={
          <>
            <button
              type="button"
              className="page-header-action-icon"
              aria-label="설정"
              onClick={() => navigate('/settings')}
            >
              <IconSettings size={20} />
            </button>
            <button
              type="button"
              className="page-header-action"
              onClick={() => {
                logout()
                navigate('/login', { replace: true })
              }}
            >
              로그아웃
            </button>
          </>
        }
      />

      <section className="panel home-lunch-panel" aria-busy={lunchLoading}>
        <div className="panel-head home-lunch-head">
          <div className="panel-head-text home-lunch-head-text">
            <h2 className="panel-title">{periodTitle}</h2>
            <p className="panel-sub home-lunch-time">{timeRange}</p>
          </div>
          <button type="button" className="link-btn" onClick={goDining}>
            전체
            <IconChevronRight size={16} />
          </button>
        </div>

        <div className="course-stack">
          {showLunchSkeleton &&
            Array.from({ length: LUNCH_SKELETON_ROWS }, (_, i) => (
              <LunchSkeletonRow key={`ls-${i}`} />
            ))}

          {!showLunchSkeleton &&
            lunchDishes.length > 0 &&
            lunchDishes.map((dish) => (
              <LunchDishRow
                key={dish.key}
                dish={dish}
                recommended={dishMatchesPrefs(dish, diningPrefsSet)}
                onPreview={setPreview}
              />
            ))}

          {!showLunchSkeleton && lunchDishes.length === 0 && (
            <div className="course-stack-empty">등록된 식단이 없습니다.</div>
          )}
        </div>
      </section>

      <ImagePreview image={preview} onClose={closePreview} />

      <section className="panel home-cafe-panel" aria-busy={!railReady}>
        <div className="panel-head">
          <div className="panel-head-text">
            <h2 className="panel-title">최근 주문</h2>
            <p className="panel-sub">
              {railReady
                ? recent.length > 0
                  ? `카페 ${cafeShops.length}곳 · 최신순`
                  : '주문 내역 없음'
                : '불러오는 중'}
            </p>
          </div>
          <button type="button" className="link-btn" onClick={() => goCafe()}>
            전체
            <IconChevronRight size={16} />
          </button>
        </div>

        <div className="home-cafe-rail">
          <div className="recent-rail">
            {!railReady &&
              Array.from({ length: RAIL_SLOTS }, (_, i) => (
                <div key={`rs-${i}`} className="recent-card is-skel" aria-hidden>
                  <div className="recent-card-thumb" />
                  <p className="recent-card-name">
                    <span className="home-skel home-skel-rail-name" />
                  </p>
                </div>
              ))}
            {railReady &&
              recent.length > 0 &&
              recent.map((item) => (
                <button
                  key={`r-${item.shopId}-${item.displayId}-${item.goodsId}-${item.lastOrderAt ?? ''}`}
                  type="button"
                  className={`recent-card${item.soldOut ? ' is-soldout' : ''}`}
                  disabled={item.soldOut || !item.displayId}
                  onClick={() => {
                    if (!item.displayId) return
                    selectShop(item.shopId)
                    navigate(`/cafe/${item.shopId}/menu?d=${item.displayId}`)
                  }}
                >
                  <div className="recent-card-thumb">
                    <MenuThumb
                      src={item.thumbnailUrl}
                      width={96}
                      height={96}
                    />
                    <span className="recent-card-shop-chip">
                      {item.shopName
                        .replace(/^kafé\s*/i, '')
                        .replace(/\s*\(.*\)$/, '')
                        .trim() || item.shopName}
                    </span>
                    {item.soldOut && (
                      <span className="recent-card-soldout">
                        <span className="recent-card-soldout-label">품절</span>
                      </span>
                    )}
                  </div>
                  <p className="recent-card-name">{item.name || '메뉴'}</p>
                </button>
              ))}
            {railReady && recent.length === 0 && (
              <button
                type="button"
                className="home-cafe-rail-empty"
                onClick={() => goCafe()}
              >
                카페 메뉴 보기
              </button>
            )}
          </div>
        </div>
      </section>

      {shopsError && (
        <div className="stack-tight">
          <ErrorBox>{shopsError}</ErrorBox>
          <button
            type="button"
            className="btn btn-ghost"
            onClick={() => void refreshShops()}
          >
            다시 시도
          </button>
        </div>
      )}

      {!shopsLoading && shops.length === 0 && !shopsError && (
        <Empty>표시할 매장이 없습니다.</Empty>
      )}
    </div>
  )
}
