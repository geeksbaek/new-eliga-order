import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { fetchDiningMenu } from '../api/eliga'
import { Empty, ErrorBox, Loading } from '../components/UiState'
import {
  congestionLabel,
  formatWon,
  formatKcal,
  todayISODate,
} from '../lib/format'
import { useShop } from '../hooks/useShop'
import type { DiningPeriod } from '../lib/types'

function shiftDate(iso: string, delta: number): string {
  const d = new Date(`${iso}T12:00:00`)
  d.setDate(d.getDate() + delta)
  return todayISODate(d)
}

export function DiningMenuPage() {
  const { shopId: shopIdParam } = useParams()
  const shopId = Number(shopIdParam || 7)
  const { selectShop, shops } = useShop()
  const shopName =
    shops.find((s) => s.shopId === shopId)?.name ?? '춘식도락(B1F)'

  const [date, setDate] = useState(todayISODate())
  const [periods, setPeriods] = useState<DiningPeriod[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    selectShop(shopId)
  }, [shopId, selectShop])

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setError(null)
    fetchDiningMenu(shopId, date)
      .then((data) => {
        if (!cancelled) setPeriods(data)
      })
      .catch((e) => {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : '식단을 불러오지 못했습니다')
          setPeriods([])
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [shopId, date])

  return (
    <div>
      <div className="row" style={{ marginBottom: 8 }}>
        <Link to="/" className="btn btn-ghost btn-sm">
          ← 매장
        </Link>
      </div>
      <h1 className="page-title">{shopName}</h1>
      <p className="page-sub">
        식당 메뉴는 조회만 가능합니다. 주문·장바구니는 카페 매장에서 이용해 주세요.
      </p>

      <div className="date-nav">
        <button
          type="button"
          className="icon-btn"
          aria-label="이전 날"
          onClick={() => setDate((d) => shiftDate(d, -1))}
        >
          ‹
        </button>
        <div className="date-label">
          {date}
          {date === todayISODate() ? ' (오늘)' : ''}
        </div>
        <button
          type="button"
          className="icon-btn"
          aria-label="다음 날"
          onClick={() => setDate((d) => shiftDate(d, 1))}
        >
          ›
        </button>
        <button
          type="button"
          className="btn btn-ghost btn-sm"
          onClick={() => setDate(todayISODate())}
        >
          오늘
        </button>
      </div>

      {loading && <Loading label="식단 불러오는 중…" />}
      {error && <ErrorBox>{error}</ErrorBox>}
      {!loading && !error && periods.length === 0 && (
        <Empty>이 날짜의 식단 정보가 없습니다.</Empty>
      )}

      {periods.map((period) => (
        <section
          key={`${period.time}-${period.startTime}`}
          className="period-block"
        >
          <div className="period-head">
            <h2>{period.time || '운영'}</h2>
            <span>
              {period.startTime} – {period.endTime}
            </span>
          </div>
          {period.courses.map((course) => (
            <article
              key={course.name}
              className={`card course-card${course.soldOut ? ' soldout' : ''}`}
            >
              <div className="course-title">
                <h3>
                  {course.name}
                  {course.soldOut ? ' (품절)' : ''}
                </h3>
                <strong>{formatWon(course.price)}</strong>
              </div>
              <div className="shop-meta" style={{ marginBottom: 10 }}>
                {course.congestion && (
                  <span className="badge">
                    {congestionLabel(course.congestion)}
                  </span>
                )}
              </div>

              <div className="meal-grid">
                {course.menus.map((m) => (
                  <div
                    key={m.name}
                    className={`meal-tile${m.soldOut ? ' soldout' : ''}`}
                  >
                    <div className="meal-thumb">
                      {m.imageUrl ? (
                        <img
                          src={m.imageUrl}
                          alt={m.name}
                          loading="lazy"
                          decoding="async"
                        />
                      ) : (
                        <div className="meal-thumb-empty" aria-hidden>
                          이미지 없음
                        </div>
                      )}
                    </div>
                    <div className="meal-body">
                      <p className="meal-name">
                        {m.name}
                        {m.soldOut ? ' (품절)' : ''}
                      </p>
                      {m.calorie != null && (
                        <p className="kcal">{formatKcal(m.calorie)}</p>
                      )}
                    </div>
                  </div>
                ))}
              </div>

              {course.origin && (
                <p className="origin-note muted">원산지 {course.origin}</p>
              )}
            </article>
          ))}
        </section>
      ))}
    </div>
  )
}
