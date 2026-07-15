import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useParams, useSearchParams } from 'react-router-dom'
import { fetchDiningMenu } from '../api/eliga'
import { Empty, ErrorBox } from '../components/UiState'
import { DatePickerSheet } from '../components/DatePickerSheet'
import { DiningPrefsSheet } from '../components/DiningPrefsSheet'
import { ImagePreview, type PreviewImage } from '../components/ImagePreview'
import { PageHeader } from '../components/PageHeader'
import { IconChevronLeft, IconChevronRight, IconStar } from '../components/Icons'
import {
  dishMatchesPrefs,
  loadDiningPrefs,
  prefsToSet,
  saveDiningPrefs,
  sortDishesByPref,
} from '../lib/dining-prefs'
import { congestionLabel, formatKcal, todayISODate } from '../lib/format'
import { MenuThumb } from '../components/MenuThumb'
import {
  dishPreviewFromGroup,
  groupDiningDishes,
  isPeriodLive,
  periodMatchesQuery,
  periodSlug,
  pickBestPeriodIndex,
  type GroupedDiningDish,
} from '../lib/dining-group'
import {
  cachePeek,
  cacheSet,
  diningKey,
} from '../lib/query-cache'
import { scrollExpandedDiningGroup } from '../lib/scroll-into-view'
import { useScrollRestore } from '../hooks/useScrollRestore'
import { useShop } from '../hooks/useShop'
import type { DiningPeriod } from '../lib/types'

function shiftDate(iso: string, delta: number): string {
  const d = new Date(`${iso}T12:00:00`)
  d.setDate(d.getDate() + delta)
  return todayISODate(d)
}

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

function formatDayLabel(iso: string): string {
  const d = new Date(`${iso}T12:00:00`)
  const wd = ['일', '월', '화', '수', '목', '금', '토'][d.getDay()]
  const today = todayISODate()
  const base = `${d.getMonth() + 1}/${d.getDate()}(${wd})`
  return iso === today ? `${base} 오늘` : base
}

function formatTimeRange(start: string, end: string): string {
  const s = (start || '').slice(0, 5)
  const e = (end || '').slice(0, 5)
  if (s && e) return `${s}–${e}`
  return s || e || ''
}

function DishRow({
  dish,
  recommended,
  onPreview,
}: {
  dish: GroupedDiningDish
  recommended?: boolean
  onPreview: (img: PreviewImage) => void
}) {
  const courseLabel = dish.courseNames.join(' · ')
  const preview = dishPreviewFromGroup(dish)

  return (
    <button
      type="button"
      className={`dining-line${dish.soldOut ? ' is-soldout' : ''}${
        recommended ? ' is-recommended' : ''
      }`}
      aria-label={`${dish.name}${recommended ? ' 추천' : ''} 상세 보기`}
      onClick={() => onPreview(preview)}
    >
      <span className="dining-thumb" aria-hidden>
        <MenuThumb src={dish.imageUrl} width={44} height={44} />
      </span>
      <div className="dining-line-main">
        <span className="dining-line-course" title={courseLabel}>
          {courseLabel}
          {recommended ? (
            <span className="dining-rec-badge">추천</span>
          ) : null}
        </span>
        <p className="dining-line-name">
          <span className="dining-line-name-text">{dish.name}</span>
          <span className="dining-meta">
            {dish.calorie != null ? formatKcal(dish.calorie) : '\u00a0'}
            {dish.soldOut ? ' · 품절' : ''}
          </span>
        </p>
      </div>
      <span
        className={`pill pill-sm pill-slot dining-line-status ${congestionClass(dish.congestion)}`}
      >
        {dish.congestion ? congestionLabel(dish.congestion) : '\u00a0'}
      </span>
    </button>
  )
}

const SKELETON_ROWS = 6

export function DiningMenuPage() {
  const { shopId: shopIdParam } = useParams()
  const [searchParams] = useSearchParams()
  const shopId = Number(shopIdParam || 7)
  const { selectShop, shops } = useShop()
  useScrollRestore()
  const shopName =
    shops.find((s) => s.shopId === shopId)?.name ?? '춘식도락(B1F)'

  const periodQuery =
    searchParams.get('period') || searchParams.get('meal') || null
  const dateQuery = searchParams.get('date')

  const [date, setDate] = useState(() => {
    if (dateQuery && /^\d{4}-\d{2}-\d{2}$/.test(dateQuery)) return dateQuery
    return todayISODate()
  })
  const [periods, setPeriods] = useState<DiningPeriod[]>(() => {
    return cachePeek(diningKey(shopId, date)) ?? []
  })
  const [loading, setLoading] = useState(() => periods.length === 0)
  const [error, setError] = useState<string | null>(null)
  /** Expanded period slugs */
  const [expanded, setExpanded] = useState<Set<string>>(() => new Set())
  const [showSoldOut, setShowSoldOut] = useState(false)
  const [preview, setPreview] = useState<PreviewImage | null>(null)
  const [calendarOpen, setCalendarOpen] = useState(false)
  const [prefsOpen, setPrefsOpen] = useState(false)
  const [prefs, setPrefs] = useState<string[]>(() => loadDiningPrefs())
  const groupRefs = useRef<Map<string, HTMLElement>>(new Map())
  const focusDone = useRef(false)

  const closePreview = useCallback(() => setPreview(null), [])
  const closeCalendar = useCallback(() => setCalendarOpen(false), [])
  const closePrefs = useCallback(() => setPrefsOpen(false), [])
  const prefsSet = useMemo(() => prefsToSet(prefs), [prefs])

  const onPrefsChange = useCallback((names: string[]) => {
    saveDiningPrefs(names)
    setPrefs(names)
  }, [])

  const toggleGroup = useCallback((slug: string) => {
    let opening = false
    setExpanded((prev) => {
      opening = !prev.has(slug)
      const next = new Set(prev)
      if (opening) next.add(slug)
      else next.delete(slug)
      return next
    })
    // After expand: scroll so the full open card sits above tab/cart chrome
    if (opening) {
      requestAnimationFrame(() => {
        scrollExpandedDiningGroup(groupRefs.current.get(slug))
      })
    }
  }, [])

  useEffect(() => {
    selectShop(shopId)
  }, [shopId, selectShop])

  useEffect(() => {
    if (dateQuery && /^\d{4}-\d{2}-\d{2}$/.test(dateQuery)) {
      setDate(dateQuery)
    }
  }, [dateQuery])

  const computeDefaultExpanded = useCallback(
    (list: DiningPeriod[], day: string, query: string | null) => {
      const next = new Set<string>()
      const isToday = day === todayISODate()
      list.forEach((p) => {
        const slug = periodSlug(p)
        if (periodMatchesQuery(p, query)) {
          next.add(slug)
          return
        }
        if (isToday && isPeriodLive(p)) {
          next.add(slug)
        }
      })
      // No live window and no query: open the best matching period only
      if (next.size === 0 && list.length > 0) {
        const best = pickBestPeriodIndex(list, { dateISO: day })
        next.add(periodSlug(list[best]))
      }
      return next
    },
    [],
  )

  const loadDining = useCallback(
    async (sid: number, day: string, force = false) => {
      const key = diningKey(sid, day)
      if (!force) {
        const hit = cachePeek<DiningPeriod[]>(key)
        if (hit) {
          setPeriods(hit)
          setExpanded(computeDefaultExpanded(hit, day, periodQuery))
          setLoading(false)
          void fetchDiningMenu(sid, day)
            .then((data) => {
              cacheSet(key, data)
              setPeriods(data)
              setExpanded(computeDefaultExpanded(data, day, periodQuery))
            })
            .catch(() => {})
          return
        }
      }
      setLoading(true)
      setError(null)
      try {
        const data = await fetchDiningMenu(sid, day)
        cacheSet(key, data)
        setPeriods(data)
        setExpanded(computeDefaultExpanded(data, day, periodQuery))
      } catch (e) {
        setError(e instanceof Error ? e.message : '식단을 불러오지 못했습니다')
        if (!cachePeek(key)) setPeriods([])
      } finally {
        setLoading(false)
      }
    },
    [computeDefaultExpanded, periodQuery],
  )

  useEffect(() => {
    focusDone.current = false
    void loadDining(shopId, date)
  }, [shopId, date, loadDining])

  // Deep-link: expand + scroll + focus target period group
  useEffect(() => {
    if (!periodQuery || loading || !periods.length || focusDone.current) return
    const target = periods.find((p) => periodMatchesQuery(p, periodQuery))
    if (!target) return
    const slug = periodSlug(target)
    setExpanded((prev) => new Set(prev).add(slug))
    const t = window.setTimeout(() => {
      const el = groupRefs.current.get(slug)
      if (!el) return
      scrollExpandedDiningGroup(el)
      el.focus({ preventScroll: true })
      el.classList.add('is-focus-flash')
      window.setTimeout(() => el.classList.remove('is-focus-flash'), 1600)
      focusDone.current = true
    }, 80)
    return () => window.clearTimeout(t)
  }, [periodQuery, loading, periods])

  const hasData = periods.length > 0
  const showEmpty = !loading && !error && periods.length === 0

  const dishesByPeriod = useMemo(
    () => periods.map((p) => groupDiningDishes(p.courses)),
    [periods],
  )

  const soldOutCount = useMemo(() => {
    let n = 0
    for (const dishes of dishesByPeriod) {
      for (const d of dishes) if (d.soldOut) n += 1
    }
    return n
  }, [dishesByPeriod])

  return (
    <div className="dining">
      <PageHeader
        title={shopName}
        trailing={
          <div className="dining-date" role="group" aria-label="날짜">
            <button
              type="button"
              className="dining-date-btn"
              aria-label="이전 날"
              onClick={() => setDate((d) => shiftDate(d, -1))}
            >
              <IconChevronLeft size={18} />
            </button>
            <button
              type="button"
              className="dining-date-label"
              aria-label={`날짜 선택, 현재 ${formatDayLabel(date)}`}
              aria-haspopup="dialog"
              aria-expanded={calendarOpen}
              onClick={() => setCalendarOpen(true)}
            >
              {formatDayLabel(date)}
            </button>
            <button
              type="button"
              className="dining-date-btn"
              aria-label="다음 날"
              onClick={() => setDate((d) => shiftDate(d, 1))}
            >
              <IconChevronRight size={18} />
            </button>
            {date !== todayISODate() && (
              <button
                type="button"
                className="dining-date-today"
                onClick={() => setDate(todayISODate())}
              >
                오늘
              </button>
            )}
          </div>
        }
      />

      <DatePickerSheet
        open={calendarOpen}
        value={date}
        onChange={setDate}
        onClose={closeCalendar}
      />

      {error && <ErrorBox>{error}</ErrorBox>}

      <div className="dining-toolbar">
        <label className="dining-filter">
          <input
            type="checkbox"
            checked={showSoldOut}
            onChange={(e) => setShowSoldOut(e.target.checked)}
          />
          <span>
            품절 메뉴 보기
            {soldOutCount > 0 ? ` (${soldOutCount})` : ''}
          </span>
        </label>
        <button
          type="button"
          className={`dining-prefs-btn${prefs.length > 0 ? ' has-prefs' : ''}`}
          onClick={() => setPrefsOpen(true)}
        >
          <IconStar size={15} filled={prefs.length > 0} />
          <span>
            선호 음식
            {prefs.length > 0 ? ` ${prefs.length}` : ''}
          </span>
        </button>
      </div>

      <DiningPrefsSheet
        open={prefsOpen}
        shopId={shopId}
        selected={prefs}
        onChange={onPrefsChange}
        onClose={closePrefs}
      />

      {showEmpty && <Empty>이 날짜의 식단이 없습니다.</Empty>}

      <div
        className={`dining-groups${loading ? ' is-dim' : ''}`}
        aria-busy={loading}
      >
        {!hasData && loading && (
          <section className="dining-group-block is-open" aria-hidden>
            <div className="dining-group-head">
              <span className="dining-group-title">불러오는 중</span>
            </div>
            <div className="dining-group-panel">
              <div className="dining-group-panel-inner">
                <div className="dining-group-body">
                  {Array.from({ length: SKELETON_ROWS }, (_, i) => (
                    <div key={i} className="dining-line dining-line-skel">
                      <span className="dining-thumb is-empty" aria-hidden />
                      <div className="dining-line-main">
                        <span className="skel-bar skel-bar-sm" />
                        <span className="skel-bar skel-bar-name" />
                      </div>
                      <span className="skel-bar skel-bar-status" aria-hidden />
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </section>
        )}

        {periods.map((p, pIdx) => {
          const slug = periodSlug(p)
          const allDishes = dishesByPeriod[pIdx] ?? []
          const visible = showSoldOut
            ? allDishes
            : allDishes.filter((d) => !d.soldOut)
          const dishes = sortDishesByPref(visible, prefsSet)
          const open = expanded.has(slug)
          const live = date === todayISODate() && isPeriodLive(p)
          const range = formatTimeRange(p.startTime, p.endTime)
          const hiddenSold = allDishes.length - dishes.length
          const recCount = dishes.filter((d) =>
            dishMatchesPrefs(d, prefsSet),
          ).length

          return (
            <section
              key={`${p.time}-${p.startTime}`}
              className={`dining-group-block${open ? ' is-open' : ''}${live ? ' is-live' : ''}${periodMatchesQuery(p, periodQuery) ? ' is-target' : ''}`}
              ref={(el) => {
                if (el) groupRefs.current.set(slug, el)
                else groupRefs.current.delete(slug)
              }}
              id={`dining-period-${slug}`}
              tabIndex={-1}
              aria-labelledby={`dining-period-title-${slug}`}
            >
              <button
                type="button"
                className="dining-group-head"
                id={`dining-period-title-${slug}`}
                aria-expanded={open}
                aria-controls={`dining-period-panel-${slug}`}
                onClick={() => toggleGroup(slug)}
              >
                <span className="dining-group-title">
                  {p.time || `시간${pIdx + 1}`}
                  {live && <span className="dining-group-live">진행 중</span>}
                </span>
                <span className="dining-group-meta">
                  {range}
                  {allDishes.length > 0
                    ? ` · ${dishes.length}개${hiddenSold > 0 && !showSoldOut ? ` · 품절 ${hiddenSold}` : ''}${recCount > 0 ? ` · 추천 ${recCount}` : ''}`
                    : ''}
                </span>
                <span className="dining-group-chevron" aria-hidden>
                  ▾
                </span>
              </button>

              <div
                className="dining-group-panel"
                id={`dining-period-panel-${slug}`}
                role="region"
                aria-labelledby={`dining-period-title-${slug}`}
                aria-hidden={!open}
                // Closed panels stay in DOM for height animation; block focus/AT
                inert={open ? undefined : true}
              >
                <div className="dining-group-panel-inner">
                  <div className="dining-group-body">
                    {dishes.length === 0 ? (
                      <div className="dining-panel-empty">
                        {allDishes.length > 0 && !showSoldOut
                          ? '표시할 메뉴가 없습니다. 품절 메뉴 보기를 켜 보세요.'
                          : '이 시간대 메뉴가 없습니다.'}
                      </div>
                    ) : (
                      dishes.map((dish) => (
                        <DishRow
                          key={dish.key}
                          dish={dish}
                          recommended={dishMatchesPrefs(dish, prefsSet)}
                          onPreview={setPreview}
                        />
                      ))
                    )}
                  </div>
                </div>
              </div>
            </section>
          )
        })}
      </div>

      <ImagePreview image={preview} onClose={closePreview} />
    </div>
  )
}
