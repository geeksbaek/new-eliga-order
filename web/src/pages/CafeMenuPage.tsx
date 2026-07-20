import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import {
  fetchCafeCategories,
  fetchCafeMenu,
  fetchCafeMenuDetail,
  fetchPopularOrders,
  fetchRecentOrders,
  prepareIsolatedQuickOrder,
} from '../api/eliga'
import { Empty, ErrorBox } from '../components/UiState'
import { ImagePreview, type PreviewImage } from '../components/ImagePreview'
import { PageHeader } from '../components/PageHeader'
import { formatWon } from '../lib/format'
import { MenuThumb } from '../components/MenuThumb'
import { CafeHeaderActions } from '../components/CafeHeaderActions'
import { QuickOrderSheet } from '../components/QuickOrderSheet'
import { IconStar } from '../components/Icons'
import { saveQuickOrderSession } from '../lib/quick-order'
import { baseMenuTitle } from '../lib/temp-variants'
import type { GoodsVariant, MenuDetail, SelectedOption } from '../lib/types'
import {
  cacheIsFresh,
  cachePeek,
  cacheSet,
  cafeCatsKey,
  cafeMenuKey,
  cafeRailKey,
} from '../lib/query-cache'
import {
  isFavorite,
  loadFavorites,
  toggleFavorite,
  type CafeFavorite,
} from '../lib/cafe-favorites'
import { schedulePrefetchCafe } from '../lib/prefetch-cafe'
import { warmImageUrls } from '../lib/image-warm'
import { ensureHorizontalVisible } from '../lib/scroll-chip'
import { KNOWN_SHOPS, listCafeShops } from '../lib/shop-rules'
import { useCartMutations } from '../hooks/useCartMutations'
import { useScrollRestore } from '../hooks/useScrollRestore'
import { useShop } from '../hooks/useShop'
import type { CafeCategory, CafeMenuItem, CafeQuickItem } from '../lib/types'

const MENU_SKELETON_COUNT = 8
const RAIL_SLOT_COUNT = 4
const FAV_ROUTE = 'favorites'

type RailCache = { recent: CafeQuickItem[]; popular: CafeQuickItem[] }
/** Category chip: all or real category id (favorites is a shop-level pill). */
type ActiveCat = number | 'all'

function catStorageKey(sid: number): string {
  return `eliga.cafe.cat:${sid}`
}

function readStoredCat(sid: number): ActiveCat | null {
  try {
    const raw = sessionStorage.getItem(catStorageKey(sid))
    if (raw == null || raw === '') return null
    if (raw === 'all') return 'all'
    const n = Number(raw)
    return Number.isFinite(n) ? n : null
  } catch {
    return null
  }
}

function writeStoredCat(sid: number, cat: ActiveCat): void {
  try {
    sessionStorage.setItem(catStorageKey(sid), String(cat))
  } catch {
    /* ignore */
  }
}

/** Menu row with shop context (needed for multi-shop favorites). */
type MenuRow = CafeMenuItem & { shopId: number; shopName: string }

function shortCafeName(name: string): string {
  return (
    name
      .replace(/^kafé\s*/i, '')
      .replace(/\s*\(.*\)$/, '')
      .trim() || name
  )
}

function withShop(
  items: CafeMenuItem[],
  shopId: number,
  shopName: string,
): MenuRow[] {
  return items.map((m) => ({ ...m, shopId, shopName }))
}

type CafeMenuPageProps = {
  /**
   * False while menu detail is shown on top (CafeShopShell keeps this page
   * mounted). Scroll restore only runs when the list is visible.
   */
  listActive?: boolean
}

export function CafeMenuPage({ listActive = true }: CafeMenuPageProps) {
  const { shopId: shopIdParam } = useParams()
  const isFavView = shopIdParam === FAV_ROUTE || shopIdParam === 'fav'
  const shopId = isFavView ? NaN : Number(shopIdParam)
  const navigate = useNavigate()
  const {
    selectShop,
    shops,
    cart,
    cartsByShop,
    getCafeHours,
    getCart,
    refreshCart,
    setCartLocal,
  } = useShop()
  // Stable key: detail URL must not overwrite list scroll storage
  useScrollRestore({
    enabled: listActive,
    storageKey: isFavView
      ? '/cafe/favorites'
      : Number.isFinite(shopId)
        ? `/cafe/${shopId}`
        : `/cafe/${shopIdParam ?? ''}`,
  })
  const [actionError, setActionError] = useState<string | null>(null)
  const [quickBusyKey, setQuickBusyKey] = useState<string | null>(null)
  const [quickOrder, setQuickOrder] = useState<{
    shopId: number
    menuName: string
    displayId: number
    detail: MenuDetail
    preferredGoodsId: number | null
    willReplaceCart: boolean
  } | null>(null)

  const { bumpMenuQty } = useCartMutations({
    onError: (err) => {
      if (err.code === 'OPTION_REQUIRED' && err.goodsId != null) {
        const menu = menus.find((m) => m.goodsId === err.goodsId)
        if (menu) {
          navigate(`/cafe/${menu.shopId}/menu?d=${menu.displayId}`)
          return
        }
      }
      const msg =
        err.error instanceof Error
          ? err.error.message
          : '장바구니 반영에 실패했습니다'
      setActionError(msg)
    },
  })

  const cafeShops = useMemo(() => listCafeShops(shops), [shops])
  const cafeShopKey = useMemo(
    () => cafeShops.map((s) => s.shopId).join(','),
    [cafeShops],
  )
  const shopName = isFavView
    ? '즐겨찾기'
    : (shops.find((s) => s.shopId === shopId)?.name ??
      KNOWN_SHOPS.find((s) => s.shopId === shopId)?.name ??
      `매장 ${shopId}`)

  const shopHours = !isFavView && Number.isFinite(shopId)
    ? getCafeHours(shopId)
    : null

  const [categories, setCategories] = useState<CafeCategory[]>(() =>
    !isFavView && Number.isFinite(shopId)
      ? (cachePeek(cafeCatsKey(shopId)) ?? [])
      : [],
  )
  // Seed from session so back-nav does not flash "전체" then the real chip.
  const [activeCat, setActiveCat] = useState<ActiveCat>(() => {
    if (isFavView || !Number.isFinite(shopId)) return 'all'
    const saved = readStoredCat(shopId)
    if (saved == null) return 'all'
    if (saved === 'all') return 'all'
    const cats = cachePeek<CafeCategory[]>(cafeCatsKey(shopId))
    if (cats && cats.some((c) => c.id === saved)) return saved
    // Cats not cached yet — still prefer stored id so chip can light up when list paints
    return saved
  })
  const [favEntries, setFavEntries] = useState<CafeFavorite[]>(() =>
    loadFavorites(),
  )
  const [menus, setMenus] = useState<MenuRow[]>(() => {
    if (isFavView) return []
    if (!Number.isFinite(shopId)) return []
    const hit = cachePeek<CafeMenuItem[]>(cafeMenuKey(shopId, 'all'))
    if (!hit) return []
    const name =
      shops.find((s) => s.shopId === shopId)?.name ??
      KNOWN_SHOPS.find((s) => s.shopId === shopId)?.name ??
      `매장 ${shopId}`
    return withShop(hit, shopId, name)
  })
  const [loading, setLoading] = useState(() => menus.length === 0)
  const [error, setError] = useState<string | null>(null)
  const [recent, setRecent] = useState<CafeQuickItem[]>(() => {
    if (!Number.isFinite(shopId)) return []
    return cachePeek<RailCache>(cafeRailKey(shopId))?.recent ?? []
  })
  const [popular, setPopular] = useState<CafeQuickItem[]>(() => {
    if (!Number.isFinite(shopId)) return []
    return cachePeek<RailCache>(cafeRailKey(shopId))?.popular ?? []
  })
  const [railReady, setRailReady] = useState(
    () =>
      Number.isFinite(shopId) && cachePeek(cafeRailKey(shopId)) != null,
  )
  const [preview, setPreview] = useState<PreviewImage | null>(null)

  /** Bumps on every shop/cat navigation so stale responses never win. */
  const menuReqId = useRef(0)
  const railReqId = useRef(0)
  const catReqId = useRef(0)
  const shopPillRefs = useRef(new Map<string, HTMLButtonElement>())
  const catChipRefs = useRef(new Map<string, HTMLButtonElement>())

  useEffect(() => {
    if (!isFavView && Number.isFinite(shopId)) selectShop(shopId)
  }, [shopId, isFavView, selectShop])

  const applyCatsAndRestore = useCallback((sid: number, cats: CafeCategory[]) => {
    setCategories((prev) => {
      if (
        prev.length === cats.length &&
        prev.every((c, i) => c.id === cats[i]?.id && c.name === cats[i]?.name)
      ) {
        return prev
      }
      return cats
    })
    const saved = readStoredCat(sid)
    const next: ActiveCat =
      saved === 'all'
        ? 'all'
        : typeof saved === 'number' && cats.some((c) => c.id === saved)
          ? saved
          : 'all'
    setActiveCat((prev) => (prev === next ? prev : next))
  }, [])

  const loadCategories = useCallback(
    async (sid: number, force = false) => {
      const req = ++catReqId.current
      const key = cafeCatsKey(sid)
      if (!force) {
        const hit = cachePeek<CafeCategory[]>(key)
        if (hit) {
          if (req === catReqId.current) applyCatsAndRestore(sid, hit)
          if (cacheIsFresh(key)) return hit
          void fetchCafeCategories(sid)
            .then((raw) => {
              if (req !== catReqId.current) return
              const cats = raw.filter((c) => c.mobileUseYn)
              cacheSet(key, cats)
              applyCatsAndRestore(sid, cats)
            })
            .catch(() => {})
          return hit
        }
      }
      try {
        const cats = (await fetchCafeCategories(sid)).filter((c) => c.mobileUseYn)
        if (req !== catReqId.current) return cats
        cacheSet(key, cats)
        applyCatsAndRestore(sid, cats)
        return cats
      } catch {
        if (req === catReqId.current) setCategories([])
        return []
      }
    },
    [applyCatsAndRestore],
  )

  /** Skip setState when list thumbs would look identical (avoids remount flash). */
  const applyMenusIfChanged = useCallback(
    (sid: number, shopLabel: string, items: CafeMenuItem[]) => {
      warmImageUrls(items.map((m) => m.thumbnailUrl))
      setMenus((prev) => {
        if (
          prev.length === items.length &&
          prev.every(
            (row, i) =>
              row.shopId === sid &&
              row.displayId === items[i].displayId &&
              row.thumbnailUrl === items[i].thumbnailUrl &&
              row.price === items[i].price &&
              row.soldOut === items[i].soldOut &&
              row.name === items[i].name &&
              row.label === items[i].label,
          )
        ) {
          return prev
        }
        return withShop(items, sid, shopLabel)
      })
    },
    [],
  )

  /** Always fetch the full shop menu once; category chips filter client-side. */
  const loadMenu = useCallback(
    async (sid: number, shopLabel: string, force = false) => {
      const req = ++menuReqId.current
      const key = cafeMenuKey(sid, 'all')
      if (!force) {
        const hit = cachePeek<CafeMenuItem[]>(key)
        if (hit) {
          if (req === menuReqId.current) {
            applyMenusIfChanged(sid, shopLabel, hit)
            setLoading(false)
            setError(null)
          }
          if (!cacheIsFresh(key)) {
            void fetchCafeMenu(sid)
              .then((items) => {
                if (req !== menuReqId.current) return
                cacheSet(key, items)
                // Soft revalidate: only update when content actually changed
                applyMenusIfChanged(sid, shopLabel, items)
              })
              .catch(() => {})
          }
          return hit
        }
      }
      if (req === menuReqId.current) {
        setLoading(true)
        setError(null)
        if (!cachePeek(key)) setMenus([])
      }
      try {
        const items = await fetchCafeMenu(sid)
        if (req !== menuReqId.current) return items
        cacheSet(key, items)
        applyMenusIfChanged(sid, shopLabel, items)
        setLoading(false)
        return items
      } catch (e) {
        if (req !== menuReqId.current) throw e
        setError(e instanceof Error ? e.message : '메뉴를 불러오지 못했습니다')
        if (!cachePeek(key)) setMenus([])
        setLoading(false)
        throw e
      }
    },
    [applyMenusIfChanged],
  )

  /** Load all cafe shops and pick favorited rows (multi-shop view). */
  const loadFavoritesView = useCallback(
    async (shopList: Array<{ shopId: number; name: string }>) => {
      const req = ++menuReqId.current
      setLoading(true)
      setError(null)
      setCategories([])
      setRecent([])
      setPopular([])
      setRailReady(true)
      setActiveCat('all')

      const entries = loadFavorites()
      setFavEntries(entries)

      // Seed from cache for instant paint
      const pool: MenuRow[] = []
      for (const s of shopList) {
        const hit = cachePeek<CafeMenuItem[]>(cafeMenuKey(s.shopId, 'all'))
        if (hit) pool.push(...withShop(hit, s.shopId, s.name))
      }
      if (pool.length && req === menuReqId.current) {
        setMenus(pool)
        setLoading(false)
      }

      try {
        const packs = await Promise.all(
          shopList.map(async (s) => {
            try {
              const items = await fetchCafeMenu(s.shopId)
              cacheSet(cafeMenuKey(s.shopId, 'all'), items)
              return withShop(items, s.shopId, s.name)
            } catch {
              return [] as MenuRow[]
            }
          }),
        )
        if (req !== menuReqId.current) return
        setMenus(packs.flat())
        setLoading(false)
      } catch (e) {
        if (req !== menuReqId.current) return
        setError(
          e instanceof Error ? e.message : '즐겨찾기를 불러오지 못했습니다',
        )
        setLoading(false)
      }
    },
    [],
  )

  const loadRail = useCallback(async (sid: number, force = false) => {
    const req = ++railReqId.current
    const key = cafeRailKey(sid)
    if (!force) {
      const hit = cachePeek<RailCache>(key)
      if (hit) {
        if (req === railReqId.current) {
          setRecent(hit.recent)
          setPopular(hit.popular)
          setRailReady(true)
        }
        if (!cacheIsFresh(key)) {
          void Promise.all([fetchRecentOrders(sid), fetchPopularOrders(sid)])
            .then(([r, p]) => {
              if (req !== railReqId.current) return
              const next = { recent: r.slice(0, 8), popular: p.slice(0, 6) }
              cacheSet(key, next)
              setRecent(next.recent)
              setPopular(next.popular)
            })
            .catch(() => {})
        }
        return
      }
    }
    if (req === railReqId.current) {
      setRailReady(false)
      setRecent([])
      setPopular([])
    }
    try {
      const [r, p] = await Promise.all([
        fetchRecentOrders(sid),
        fetchPopularOrders(sid),
      ])
      if (req !== railReqId.current) return
      const next = { recent: r.slice(0, 8), popular: p.slice(0, 6) }
      cacheSet(key, next)
      setRecent(next.recent)
      setPopular(next.popular)
    } catch {
      if (req !== railReqId.current) return
      setRecent([])
      setPopular([])
    } finally {
      if (req === railReqId.current) setRailReady(true)
    }
  }, [])

  useEffect(() => {
    menuReqId.current += 1
    railReqId.current += 1
    catReqId.current += 1
    setActionError(null)
    setError(null)
    setFavEntries(loadFavorites())

    if (isFavView) {
      setActiveCat('all')
      const list =
        cafeShops.length > 0
          ? cafeShops.map((s) => ({ shopId: s.shopId, name: s.name }))
          : KNOWN_SHOPS.filter((s) => s.type === 'CAFE').map((s) => ({
              shopId: s.shopId,
              name: s.name,
            }))
      void loadFavoritesView(list)
      return
    }

    if (!Number.isFinite(shopId)) return

    const label =
      shops.find((s) => s.shopId === shopId)?.name ??
      KNOWN_SHOPS.find((s) => s.shopId === shopId)?.name ??
      `매장 ${shopId}`

    const cachedMenu = cachePeek<CafeMenuItem[]>(cafeMenuKey(shopId, 'all'))
    const cachedCats = cachePeek<CafeCategory[]>(cafeCatsKey(shopId))
    const cachedRail = cachePeek<RailCache>(cafeRailKey(shopId))
    if (cachedMenu) {
      // Skip setState when identical — avoids remount flash of sticky strips + rows
      applyMenusIfChanged(shopId, label, cachedMenu)
      setLoading(false)
    } else {
      setMenus([])
      setLoading(true)
    }
    if (cachedCats) applyCatsAndRestore(shopId, cachedCats)
    else {
      // Shop switch without cache — clear so previous shop chips don't linger
      setCategories([])
      const saved = readStoredCat(shopId)
      setActiveCat(saved ?? 'all')
    }
    if (cachedRail) {
      setRecent(cachedRail.recent)
      setPopular(cachedRail.popular)
      setRailReady(true)
    } else {
      setRecent([])
      setPopular([])
      setRailReady(false)
    }
    void loadCategories(shopId)
    void loadMenu(shopId, label)
    void loadRail(shopId)
  }, [
    shopId,
    isFavView,
    cafeShopKey,
    cafeShops,
    shops,
    applyCatsAndRestore,
    applyMenusIfChanged,
    loadCategories,
    loadMenu,
    loadRail,
    loadFavoritesView,
  ])

  // Persist last category for this shop
  useEffect(() => {
    if (isFavView || !Number.isFinite(shopId)) return
    writeStoredCat(shopId, activeCat)
  }, [shopId, activeCat, isFavView])

  // Keep active cafe pill / category chip in horizontal view before paint
  // (rAF left one frame of strip at scrollLeft=0 → visible chip jump on back).
  useLayoutEffect(() => {
    if (isFavView) return
    ensureHorizontalVisible(shopPillRefs.current.get(String(shopId)))
  }, [shopId, isFavView, cafeShops.length])

  useLayoutEffect(() => {
    if (isFavView) return
    const key = activeCat === 'all' ? 'all' : String(activeCat)
    ensureHorizontalVisible(catChipRefs.current.get(key))
  }, [activeCat, categories, isFavView])

  // Prefetch sibling cafe shops when the pill strip is available.
  useEffect(() => {
    if (isFavView) {
      for (const s of cafeShops) schedulePrefetchCafe(s.shopId)
      return
    }
    if (!Number.isFinite(shopId)) return
    for (const s of cafeShops) {
      if (s.shopId !== shopId) schedulePrefetchCafe(s.shopId)
    }
  }, [shopId, cafeShops, isFavView])

  /** Full list for current shop, or multi-shop favorites ordered by storage. */
  const visibleMenus = useMemo(() => {
    if (isFavView) {
      const byKey = new Map(
        menus.map((m) => [`${m.shopId}:${m.displayId}`, m] as const),
      )
      const byDisplay = new Map<number, MenuRow[]>()
      for (const m of menus) {
        const list = byDisplay.get(m.displayId) ?? []
        list.push(m)
        byDisplay.set(m.displayId, list)
      }
      const ordered: MenuRow[] = []
      for (const e of favEntries) {
        if (e.shopId > 0) {
          const hit = byKey.get(`${e.shopId}:${e.displayId}`)
          if (hit) ordered.push(hit)
          continue
        }
        // Legacy entries without shopId: take first match across shops
        const hits = byDisplay.get(e.displayId)
        if (hits?.length) ordered.push(hits[0])
      }
      return ordered
    }
    if (activeCat === 'all') return menus
    return menus.filter((m) => m.categoryId === activeCat)
  }, [menus, activeCat, isFavView, favEntries])

  /**
   * Per-shop list: 즐겨찾기 → BEST → NEW → 전체 메뉴.
   * Favorited items appear only in the 즐겨찾기 block (no duplicate below).
   * Global favorites view stays a flat multi-shop list.
   */
  const menuSections = useMemo(() => {
    if (isFavView) {
      return visibleMenus.length
        ? [{ key: 'fav-all', title: null as string | null, items: visibleMenus }]
        : []
    }

    const fav: MenuRow[] = []
    const best: MenuRow[] = []
    const neu: MenuRow[] = []
    const rest: MenuRow[] = []
    // Preserve favEntries order for the shop section
    const visibleByKey = new Map<string, MenuRow>()
    for (const m of visibleMenus) {
      visibleByKey.set(`${m.shopId}:${m.displayId}`, m)
    }
    const claimed = new Set<string>()
    for (const e of favEntries) {
      if (e.shopId > 0 && Number.isFinite(shopId) && e.shopId !== shopId) {
        continue
      }
      const key =
        e.shopId > 0
          ? `${e.shopId}:${e.displayId}`
          : Number.isFinite(shopId)
            ? `${shopId}:${e.displayId}`
            : ''
      if (!key) continue
      const hit = visibleByKey.get(key)
      if (!hit || claimed.has(key)) continue
      fav.push(hit)
      claimed.add(key)
    }
    for (const m of visibleMenus) {
      const key = `${m.shopId}:${m.displayId}`
      if (claimed.has(key)) continue
      const u = (m.label || '').toUpperCase()
      if (u === 'BEST') best.push(m)
      else if (u === 'NEW') neu.push(m)
      else rest.push(m)
    }

    const sections: Array<{
      key: string
      title: string | null
      items: MenuRow[]
    }> = []
    if (fav.length) {
      sections.push({ key: 'fav', title: '즐겨찾기', items: fav })
    }
    if (best.length) sections.push({ key: 'best', title: 'BEST', items: best })
    if (neu.length) sections.push({ key: 'new', title: 'NEW', items: neu })
    if (rest.length) {
      const hasHead = fav.length > 0 || best.length > 0 || neu.length > 0
      sections.push({
        key: 'rest',
        title: hasHead ? '전체 메뉴' : null,
        items: rest,
      })
    }
    return sections
  }, [visibleMenus, isFavView, favEntries, shopId])

  function toggleFav(item: MenuRow) {
    const next = toggleFavorite(item.displayId, item.shopId)
    setFavEntries(next)
  }

  const railItems = recent.length > 0 ? recent : popular
  const railLabel = recent.length > 0 ? '다시 주문' : '인기'
  const showMenuSkeleton = loading && menus.length === 0

  if (!isFavView && !Number.isFinite(shopId)) {
    return (
      <Empty>
        잘못된 매장입니다. <Link to="/">홈</Link>
      </Empty>
    )
  }

  function openDetail(item: MenuRow) {
    navigate(`/cafe/${item.shopId}/menu?d=${item.displayId}`)
  }

  /** qty key: shopId:goodsId so favorites can show every cafe's cart */
  const qtyByShopGoods = useMemo(() => {
    const map = new Map<string, number>()
    for (const [sidStr, c] of Object.entries(cartsByShop)) {
      const sid = Number(sidStr)
      for (const line of c.items) {
        const k = `${sid}:${line.goodsId}`
        map.set(k, (map.get(k) ?? 0) + line.qty)
      }
    }
    // Fallback: selected cart if not yet in map (race)
    for (const line of cart.items) {
      const sid = cart.shopId ?? shopId
      if (!Number.isFinite(sid)) continue
      const k = `${sid}:${line.goodsId}`
      if (!map.has(k)) map.set(k, line.qty)
    }
    return map
  }, [cartsByShop, cart.items, cart.shopId, shopId])

  function bumpQty(item: MenuRow, delta: number) {
    if (item.soldOut) return
    if (delta > 0) {
      const hours = getCafeHours(item.shopId)
      if (!hours.orderable) {
        setActionError(hours.message)
        return
      }
    }
    if (item.goodsId == null) {
      if (delta > 0) openDetail(item)
      return
    }
    setActionError(null)
    selectShop(item.shopId)
    const result = bumpMenuQty(item, delta, item.shopId)
    if (result.ok === false && result.reason === 'no-goods' && delta > 0) {
      openDetail(item)
    }
  }

  const runIsolatedQuickOrder = useCallback(
    async (
      shopIdArg: number,
      displayId: number,
      menuName: string,
      variant: GoodsVariant,
      options: SelectedOption[],
    ) => {
      const busyKey = `${shopIdArg}:${displayId}`
      setQuickBusyKey(busyKey)
      setActionError(null)
      try {
        selectShop(shopIdArg)
        const { cart: isolated, stashed } = await prepareIsolatedQuickOrder({
          shopId: shopIdArg,
          goodsId: variant.goodsId,
          options,
        })
        setCartLocal(isolated, shopIdArg)
        saveQuickOrderSession({
          shopId: shopIdArg,
          expectedGoodsId: variant.goodsId,
          expectedQty: 1,
          stashed,
          menuName,
          createdAt: Date.now(),
        })
        setQuickOrder(null)
        navigate('/order/confirm', {
          state: { quickOrder: true, shopId: shopIdArg },
        })
      } catch (e) {
        setActionError(
          e instanceof Error ? e.message : '바로 주문 준비에 실패했습니다',
        )
        await refreshCart({ silent: true, shopId: shopIdArg, force: true })
      } finally {
        setQuickBusyKey(null)
      }
    },
    [navigate, refreshCart, selectShop, setCartLocal],
  )

  async function startQuickOrder(item: MenuRow) {
    if (item.soldOut) return
    const hours = getCafeHours(item.shopId)
    if (!hours.orderable) {
      setActionError(hours.message)
      return
    }

    const busyKey = `${item.shopId}:${item.displayId}`
    setQuickBusyKey(busyKey)
    setActionError(null)
    setQuickOrder(null)

    try {
      const detail = await fetchCafeMenuDetail(item.displayId)
      if (!detail.variants.length) {
        setActionError('주문 가능한 옵션이 없습니다')
        setQuickBusyKey(null)
        return
      }
      const title =
        baseMenuTitle(item.name) ||
        baseMenuTitle(detail.variants[0]?.name ?? item.name)
      const existing = getCart(item.shopId)
      setQuickOrder({
        shopId: item.shopId,
        menuName: title,
        displayId: item.displayId,
        detail,
        preferredGoodsId: item.goodsId,
        willReplaceCart: existing.items.length > 0,
      })
      setQuickBusyKey(null)
    } catch (e) {
      setActionError(
        e instanceof Error ? e.message : '메뉴 정보를 불러오지 못했습니다',
      )
      setQuickBusyKey(null)
    }
  }

  function onQuickOrderConfirm(
    variant: GoodsVariant,
    options: SelectedOption[],
  ) {
    if (!quickOrder) return
    void runIsolatedQuickOrder(
      quickOrder.shopId,
      quickOrder.displayId,
      quickOrder.menuName,
      variant,
      options,
    )
  }

  return (
      <div className="cafe">
        {/* One sticky stack: GNB + shop pills + category chips (no offset math) */}
        <div className="cafe-sticky-top">
          <PageHeader
            title={shopName}
            trailing={
              <CafeHeaderActions active={isFavView ? 'fav' : null} />
            }
          />

          <div
            className="shop-pills shop-pills-scroll cafe-shop-pills"
            role="list"
            data-hscroll
          >
            {cafeShops.map((s) => (
              <button
                key={s.shopId}
                type="button"
                role="listitem"
                className={`shop-pill${
                  !isFavView && s.shopId === shopId ? ' is-active' : ''
                }`}
                ref={(el) => {
                  const k = String(s.shopId)
                  if (el) shopPillRefs.current.set(k, el)
                  else shopPillRefs.current.delete(k)
                }}
                onPointerEnter={() => schedulePrefetchCafe(s.shopId)}
                onFocus={() => schedulePrefetchCafe(s.shopId)}
                onClick={() => {
                  if (!isFavView && s.shopId === shopId) return
                  selectShop(s.shopId)
                  navigate(`/cafe/${s.shopId}`)
                }}
              >
                {s.name}
                {(() => {
                  const h = getCafeHours(s.shopId)
                  if (h.reason === 'unknown') return null
                  if (h.orderable) return null
                  return (
                    <span className="shop-pill-closed" aria-label="영업 종료">
                      마감
                    </span>
                  )
                })()}
              </button>
            ))}
          </div>

          {!isFavView && (
            <div
              className="chip-strip"
              role="tablist"
              aria-label="카테고리"
              data-hscroll
            >
              <button
                type="button"
                className={`chip${activeCat === 'all' ? ' is-active' : ''}`}
                ref={(el) => {
                  if (el) catChipRefs.current.set('all', el)
                  else catChipRefs.current.delete('all')
                }}
                onClick={() => setActiveCat('all')}
              >
                전체
              </button>
              {categories.map((c) => (
                <button
                  key={c.id}
                  type="button"
                  className={`chip${activeCat === c.id ? ' is-active' : ''}`}
                  ref={(el) => {
                    const k = String(c.id)
                    if (el) catChipRefs.current.set(k, el)
                    else catChipRefs.current.delete(k)
                  }}
                  onClick={() => setActiveCat(c.id)}
                >
                  {c.name}
                </button>
              ))}
            </div>
          )}
        </div>

        {!isFavView && shopHours && !shopHours.orderable && (
          <div
            className={`cafe-hours-banner${
              shopHours.reason === 'unknown' ? ' is-muted' : ' is-closed'
            }`}
            role="status"
          >
            {shopHours.message}
          </div>
        )}

        {!isFavView && (
          <section className="cafe-rail-block" aria-busy={!railReady}>
            <h2 className="rail-title">
              {!railReady
                ? '불러오는 중'
                : railItems.length > 0
                  ? railLabel
                  : '추천'}
            </h2>
            <div className="recent-rail">
              {!railReady &&
                Array.from({ length: RAIL_SLOT_COUNT }, (_, i) => (
                  <div
                    key={`rail-skel-${i}`}
                    className="recent-card is-skel"
                    aria-hidden
                  >
                    <div className="recent-card-thumb" />
                    <p className="recent-card-name">
                      <span className="cafe-skel-line" />
                    </p>
                  </div>
                ))}
              {railReady &&
                railItems.length > 0 &&
                railItems.map((item) => (
                  <button
                    key={`${railLabel}-${item.displayId}-${item.goodsId}`}
                    type="button"
                    className={`recent-card${item.soldOut ? ' is-soldout' : ''}`}
                    disabled={item.soldOut || !item.displayId}
                    onClick={() => {
                      if (!item.displayId) return
                      navigate(`/cafe/${shopId}/menu?d=${item.displayId}`)
                    }}
                  >
                    <div className="recent-card-thumb">
                      <MenuThumb
                        src={item.thumbnailUrl}
                        width={96}
                        height={96}
                      />
                      {item.soldOut && (
                        <span className="recent-card-soldout">
                          <span className="recent-card-soldout-label">품절</span>
                        </span>
                      )}
                    </div>
                    <p className="recent-card-name">{item.name || '메뉴'}</p>
                  </button>
                ))}
              {railReady && railItems.length === 0 && (
                <div className="cafe-rail-empty" aria-live="polite">
                  최근·인기 메뉴가 없습니다
                </div>
              )}
            </div>
          </section>
        )}

        {error && <ErrorBox>{error}</ErrorBox>}
        {actionError && <ErrorBox>{actionError}</ErrorBox>}

        <div
          className={`menu-dense${loading && menus.length > 0 ? ' is-dim' : ''}`}
          aria-busy={loading}
        >
          {showMenuSkeleton &&
            Array.from({ length: MENU_SKELETON_COUNT }, (_, i) => (
              <div
                key={`menu-skel-${i}`}
                className="menu-row is-skel"
                aria-hidden
              >
                <div className="menu-row-thumb-wrap" aria-hidden>
                  <div className="menu-row-thumb is-empty" />
                  <span className="menu-row-price menu-row-price-overlay">
                    <span className="cafe-skel-line cafe-skel-price" />
                  </span>
                </div>
                <div className="menu-row-main">
                  <div className="menu-row-title">
                    <span className="cafe-skel-line cafe-skel-name" />
                  </div>
                  <p className="menu-row-desc">
                    <span className="cafe-skel-line cafe-skel-desc" />
                  </p>
                </div>
                <div className="menu-row-side">
                  <div className="menu-qty" aria-hidden>
                    <span className="menu-qty-btn" />
                    <span className="menu-qty-val">0</span>
                    <span className="menu-qty-btn" />
                  </div>
                </div>
              </div>
            ))}

          {!showMenuSkeleton &&
            menuSections.map((section) => (
              <div key={section.key} className="cafe-menu-section">
                {section.title && (
                  <h3
                    className={`cafe-menu-section-title${
                      section.key === 'fav'
                        ? ' is-fav'
                        : section.key === 'best'
                          ? ' is-best'
                          : section.key === 'new'
                            ? ' is-new'
                            : ''
                    }`}
                  >
                    {section.title}
                  </h3>
                )}
                {section.items.map((item) => {
                  const goodsId = item.goodsId
                  const qty =
                    goodsId != null
                      ? (qtyByShopGoods.get(`${item.shopId}:${goodsId}`) ?? 0)
                      : 0
                  const itemHours = getCafeHours(item.shopId)
                  const orderBlocked =
                    item.soldOut || !itemHours.orderable
                  const quickKey = `${item.shopId}:${item.displayId}`
                  const quickBusy = quickBusyKey === quickKey
                  const labelU = (item.label || '').toUpperCase()
                  const tagClass =
                    labelU === 'BEST'
                      ? 'tag tag-best'
                      : labelU === 'NEW'
                        ? 'tag tag-new'
                        : item.label
                          ? 'tag tag-hot'
                          : ''
                  const starred = isFavorite(
                    item.displayId,
                    item.shopId,
                    favEntries,
                  )
                  return (
                    <div
                      key={`${item.shopId}-${item.displayId}`}
                      className={`menu-row menu-row-with-quick${item.soldOut ? ' is-soldout' : ''}${!item.soldOut && !itemHours.orderable ? ' is-closed' : ''}${qty > 0 ? ' is-in-cart' : ''}`}
                    >
                      <div className="menu-row-thumb-wrap">
                        <button
                          type="button"
                          className="menu-row-thumb"
                          aria-label={`${item.name} 사진 크게 보기`}
                          onClick={() =>
                            setPreview({
                              src: item.thumbnailUrl,
                              alt: item.name,
                              caption: item.name,
                              detail: item.description?.trim() || undefined,
                            })
                          }
                        >
                          <MenuThumb
                            src={item.thumbnailUrl}
                            width={56}
                            height={56}
                            loading="eager"
                            decoding="sync"
                          />
                          <span className="menu-row-price menu-row-price-overlay">
                            {formatWon(item.price)}
                          </span>
                        </button>
                        <button
                          type="button"
                          className={`menu-fav-btn${starred ? ' is-on' : ''}`}
                          aria-label={
                            starred
                              ? `${item.name} 즐겨찾기 해제`
                              : `${item.name} 즐겨찾기`
                          }
                          aria-pressed={starred}
                          onClick={() => toggleFav(item)}
                        >
                          <IconStar size={13} filled={starred} />
                        </button>
                      </div>
                      <button
                        type="button"
                        className="menu-row-main menu-row-main-btn"
                        onClick={() => openDetail(item)}
                      >
                        <div className="menu-row-title">
                          {isFavView ? (
                            <span className="tag tag-shop">
                              {shortCafeName(item.shopName)}
                            </span>
                          ) : null}
                          {item.label ? (
                            <span className={tagClass}>{item.label}</span>
                          ) : null}
                          <span className="menu-row-name">{item.name}</span>
                        </div>
                        <p className="menu-row-desc">
                          {item.description?.trim() || '\u00a0'}
                        </p>
                      </button>
                      <div className="menu-row-side">
                        {item.soldOut ? (
                          <span className="menu-qty is-disabled" aria-hidden>
                            품절
                          </span>
                        ) : !itemHours.orderable && qty <= 0 ? (
                          <span
                            className="menu-qty is-disabled"
                            title={itemHours.message}
                          >
                            마감
                          </span>
                        ) : (
                          <div
                            className="menu-row-actions"
                            onClick={(e) => e.stopPropagation()}
                          >
                            <div className="menu-qty">
                              <button
                                type="button"
                                className="menu-qty-btn"
                                aria-label={`${item.name} 수량 감소`}
                                disabled={qty <= 0 || quickBusy}
                                onClick={() => bumpQty(item, -1)}
                              >
                                −
                              </button>
                              <span className="menu-qty-val" aria-live="polite">
                                {qty}
                              </span>
                              <button
                                type="button"
                                className="menu-qty-btn menu-qty-btn-plus"
                                aria-label={`${item.name} 수량 증가`}
                                disabled={orderBlocked || quickBusy}
                                onClick={() => bumpQty(item, 1)}
                              >
                                +
                              </button>
                            </div>
                            <button
                              type="button"
                              className="menu-quick-order-btn"
                              disabled={orderBlocked || quickBusy}
                              aria-label={`${item.name} 바로 주문`}
                              onClick={() => void startQuickOrder(item)}
                            >
                              {quickBusy ? '준비 중' : '바로 주문'}
                            </button>
                          </div>
                        )}
                      </div>
                    </div>
                  )
                })}
              </div>
            ))}

          {!showMenuSkeleton &&
            !loading &&
            !error &&
            visibleMenus.length === 0 && (
              <p className="menu-list-empty">
                {isFavView
                  ? '즐겨찾기한 메뉴가 없습니다. 별 아이콘으로 추가해 보세요.'
                  : menus.length === 0
                    ? '메뉴가 없습니다.'
                    : '이 카테고리에 메뉴가 없습니다.'}
              </p>
            )}
        </div>

        <ImagePreview image={preview} onClose={() => setPreview(null)} />
        {quickOrder && (
          <QuickOrderSheet
            open
            menuName={quickOrder.menuName}
            detail={quickOrder.detail}
            preferredGoodsId={quickOrder.preferredGoodsId}
            busy={quickBusyKey != null}
            willReplaceCart={quickOrder.willReplaceCart}
            onConfirm={onQuickOrderConfirm}
            onClose={() => {
              if (quickBusyKey != null) return
              setQuickOrder(null)
            }}
          />
        )}
      </div>
  )
}
