import { useEffect, useId, useMemo, useState } from 'react'
import { createPortal } from 'react-dom'
import { fetchDiningMenuRange } from '../api/eliga'
import {
  CATALOG_LOOKBACK_DAYS,
  extractFoodNamesFromPeriods,
  isCatalogFresh,
  loadDiningCatalog,
  normalizeFoodName,
  saveDiningCatalog,
} from '../lib/dining-prefs'
import { todayISODate } from '../lib/format'

type Props = {
  open: boolean
  shopId: number
  selected: string[]
  onChange: (names: string[]) => void
  onClose: () => void
}

function lookbackStartISO(days: number): string {
  const d = new Date()
  d.setDate(d.getDate() - days)
  return todayISODate(d)
}

export function DiningPrefsSheet({
  open,
  shopId,
  selected,
  onChange,
  onClose,
}: Props) {
  const titleId = useId()
  const [query, setQuery] = useState('')
  const [catalog, setCatalog] = useState<string[]>(() => {
    const hit = loadDiningCatalog(shopId)
    return hit?.names ?? []
  })
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const selectedSet = useMemo(
    () => new Set(selected.map(normalizeFoodName)),
    [selected],
  )

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])

  useEffect(() => {
    if (!open) return
    let cancelled = false
    const cached = loadDiningCatalog(shopId)
    if (cached && isCatalogFresh(cached)) {
      setCatalog(cached.names)
      setLoading(false)
      setError(null)
      return
    }
    if (cached?.names.length) {
      setCatalog(cached.names)
    }
    setLoading(true)
    setError(null)
    const end = todayISODate()
    const start = lookbackStartISO(CATALOG_LOOKBACK_DAYS)
    void fetchDiningMenuRange(shopId, start, end)
      .then((periods) => {
        if (cancelled) return
        const names = extractFoodNamesFromPeriods(periods)
        saveDiningCatalog({ shopId, at: Date.now(), names })
        setCatalog(names)
      })
      .catch((e) => {
        if (cancelled) return
        setError(
          e instanceof Error
            ? e.message
            : '과거 식단을 불러오지 못했습니다',
        )
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [open, shopId])

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return catalog
    return catalog.filter((n) => n.toLowerCase().includes(q))
  }, [catalog, query])

  /** Selected chips first, then the rest (search still applies). */
  const ordered = useMemo(() => {
    const on: string[] = []
    const off: string[] = []
    for (const name of filtered) {
      if (selectedSet.has(normalizeFoodName(name))) on.push(name)
      else off.push(name)
    }
    return [...on, ...off]
  }, [filtered, selectedSet])

  function toggle(name: string) {
    const n = normalizeFoodName(name)
    if (selectedSet.has(n)) {
      onChange(selected.filter((x) => normalizeFoodName(x) !== n))
    } else {
      onChange([...selected, n])
    }
  }

  if (!open || typeof document === 'undefined') return null

  return createPortal(
    <div className="date-sheet" role="presentation" onClick={onClose}>
      <div
        className="date-sheet-panel dining-prefs-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="date-sheet-handle" aria-hidden />
        <header className="dining-prefs-head">
          <h2 id={titleId} className="date-sheet-title">
            선호 음식
          </h2>
          <p className="dining-prefs-sub">
            과거 식단의 개별 반찬·메뉴입니다. 칩을 눌러 고르면, 오늘 식단에
            포함될 때 추천으로 표시됩니다.
          </p>
        </header>

        <div className="dining-prefs-toolbar">
          <input
            type="search"
            className="dining-prefs-search"
            placeholder="반찬·메뉴 검색"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            aria-label="선호 음식 검색"
          />
          <span className="dining-prefs-count">
            {selected.length}개 선택
            {loading ? ' · 목록 불러오는 중' : ` · 전체 ${catalog.length}`}
          </span>
        </div>

        {error && <p className="dining-prefs-error">{error}</p>}

        <div
          className="dining-prefs-chips"
          role="listbox"
          aria-label="선호 음식 목록"
          aria-multiselectable="true"
        >
          {ordered.length === 0 && !loading && (
            <p className="dining-prefs-empty">
              {catalog.length === 0
                ? '불러온 반찬이 없습니다.'
                : '검색 결과가 없습니다.'}
            </p>
          )}
          {ordered.map((name) => {
            const on = selectedSet.has(normalizeFoodName(name))
            return (
              <button
                key={name}
                type="button"
                role="option"
                aria-selected={on}
                className={`dining-pref-chip${on ? ' is-on' : ''}`}
                onClick={() => toggle(name)}
              >
                {name}
              </button>
            )
          })}
        </div>

        <div className="date-sheet-actions">
          <button
            type="button"
            className="btn btn-ghost btn-sm"
            onClick={() => onChange([])}
            disabled={selected.length === 0}
          >
            전체 해제
          </button>
          <button
            type="button"
            className="btn btn-primary btn-sm"
            onClick={onClose}
          >
            완료
          </button>
        </div>
      </div>
    </div>,
    document.body,
  )
}
