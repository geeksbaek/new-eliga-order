import { useEffect, useId, useMemo, useState } from 'react'
import { createPortal } from 'react-dom'
import { todayISODate } from '../lib/format'
import { IconChevronLeft, IconChevronRight } from './Icons'

type Props = {
  open: boolean
  value: string
  onChange: (iso: string) => void
  onClose: () => void
  /** Inclusive range; defaults ±90 days from today */
  minISO?: string
  maxISO?: string
}

function parseISO(iso: string): Date {
  return new Date(`${iso}T12:00:00`)
}

function monthLabel(y: number, m0: number): string {
  return `${y}년 ${m0 + 1}월`
}

function buildCells(y: number, m0: number): Array<{ iso: string; day: number; inMonth: boolean }> {
  const first = new Date(y, m0, 1)
  const startPad = first.getDay() // 0 Sun
  const daysInMonth = new Date(y, m0 + 1, 0).getDate()
  const prevDays = new Date(y, m0, 0).getDate()
  const cells: Array<{ iso: string; day: number; inMonth: boolean }> = []

  for (let i = 0; i < startPad; i++) {
    const day = prevDays - startPad + 1 + i
    const d = new Date(y, m0 - 1, day)
    cells.push({ iso: todayISODate(d), day, inMonth: false })
  }
  for (let day = 1; day <= daysInMonth; day++) {
    const d = new Date(y, m0, day)
    cells.push({ iso: todayISODate(d), day, inMonth: true })
  }
  while (cells.length % 7 !== 0) {
    const day = cells.length - (startPad + daysInMonth) + 1
    const d = new Date(y, m0 + 1, day)
    cells.push({ iso: todayISODate(d), day, inMonth: false })
  }
  return cells
}

export function DatePickerSheet({
  open,
  value,
  onChange,
  onClose,
  minISO,
  maxISO,
}: Props) {
  const titleId = useId()
  const today = todayISODate()
  const min = minISO ?? todayISODate(new Date(Date.now() - 90 * 86400000))
  const max = maxISO ?? todayISODate(new Date(Date.now() + 30 * 86400000))

  const selected = parseISO(value)
  const [viewY, setViewY] = useState(selected.getFullYear())
  const [viewM, setViewM] = useState(selected.getMonth())

  useEffect(() => {
    if (!open) return
    const d = parseISO(value)
    setViewY(d.getFullYear())
    setViewM(d.getMonth())
  }, [open, value])

  useEffect(() => {
    if (!open) return
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => {
      document.body.style.overflow = prev
      window.removeEventListener('keydown', onKey)
    }
  }, [open, onClose])

  const cells = useMemo(() => buildCells(viewY, viewM), [viewY, viewM])

  function shiftMonth(delta: number) {
    const d = new Date(viewY, viewM + delta, 1)
    setViewY(d.getFullYear())
    setViewM(d.getMonth())
  }

  function pick(iso: string) {
    if (iso < min || iso > max) return
    onChange(iso)
    onClose()
  }

  if (!open || typeof document === 'undefined') return null

  return createPortal(
    <div className="date-sheet" role="presentation" onClick={onClose}>
      <div
        className="date-sheet-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="date-sheet-handle" aria-hidden />
        <header className="date-sheet-head">
          <button
            type="button"
            className="date-sheet-nav"
            aria-label="이전 달"
            onClick={() => shiftMonth(-1)}
          >
            <IconChevronLeft size={20} />
          </button>
          <h2 id={titleId} className="date-sheet-title">
            {monthLabel(viewY, viewM)}
          </h2>
          <button
            type="button"
            className="date-sheet-nav"
            aria-label="다음 달"
            onClick={() => shiftMonth(1)}
          >
            <IconChevronRight size={20} />
          </button>
        </header>

        <div className="date-sheet-weekdays" aria-hidden>
          {['일', '월', '화', '수', '목', '금', '토'].map((w) => (
            <span key={w}>{w}</span>
          ))}
        </div>

        <div className="date-sheet-grid" role="grid" aria-label="날짜 선택">
          {cells.map((c) => {
            const disabled = c.iso < min || c.iso > max
            const isSelected = c.iso === value
            const isToday = c.iso === today
            return (
              <button
                key={`${c.iso}-${c.inMonth ? 'm' : 'o'}`}
                type="button"
                role="gridcell"
                disabled={disabled}
                className={[
                  'date-sheet-day',
                  c.inMonth ? '' : 'is-out',
                  isSelected ? 'is-selected' : '',
                  isToday ? 'is-today' : '',
                ]
                  .filter(Boolean)
                  .join(' ')}
                aria-label={c.iso}
                aria-current={isSelected ? 'date' : undefined}
                onClick={() => pick(c.iso)}
              >
                {c.day}
              </button>
            )
          })}
        </div>

        <div className="date-sheet-actions">
          <button
            type="button"
            className="btn btn-ghost btn-sm"
            onClick={() => pick(today)}
            disabled={today < min || today > max}
          >
            오늘
          </button>
          <button type="button" className="btn btn-primary btn-sm" onClick={onClose}>
            닫기
          </button>
        </div>
      </div>
    </div>,
    document.body,
  )
}
