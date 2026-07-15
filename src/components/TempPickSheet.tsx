import { useEffect, useId } from 'react'
import { createPortal } from 'react-dom'
import type { TempPickOption } from '../lib/temp-variants'
import { formatWon } from '../lib/format'

type Props = {
  open: boolean
  menuName: string
  options: TempPickOption[]
  busy?: boolean
  /** Existing cart will be stashed and cleared for isolation. */
  willReplaceCart?: boolean
  onPick: (option: TempPickOption) => void
  onClose: () => void
}

/**
 * Bottom sheet to choose ICE vs HOT before isolated quick order.
 */
export function TempPickSheet({
  open,
  menuName,
  options,
  busy = false,
  willReplaceCart = false,
  onPick,
  onClose,
}: Props) {
  const titleId = useId()

  useEffect(() => {
    if (!open) return
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape' && !busy) onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => {
      document.body.style.overflow = prev
      window.removeEventListener('keydown', onKey)
    }
  }, [open, busy, onClose])

  if (!open || typeof document === 'undefined') return null

  return createPortal(
    <div
      className="date-sheet"
      role="presentation"
      onClick={() => {
        if (!busy) onClose()
      }}
    >
      <div
        className="date-sheet-panel temp-pick-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="date-sheet-handle" aria-hidden />
        <header className="temp-pick-head">
          <h2 id={titleId} className="date-sheet-title">
            온도 선택
          </h2>
          <p className="temp-pick-sub">{menuName}</p>
          <p className="temp-pick-hint">
            기본 옵션으로 1잔만 바로 주문합니다. 기존 장바구니 항목은 이 결제에
            포함되지 않습니다.
            {willReplaceCart
              ? ' 주문 확인을 취소하면 이전 장바구니를 복구합니다.'
              : ''}
          </p>
        </header>

        <div className="temp-pick-options" role="group" aria-label="온도">
          {options.map((opt) => (
            <button
              key={opt.variant.goodsId}
              type="button"
              className={`temp-pick-btn temp-pick-btn-${opt.kind}`}
              disabled={busy || opt.variant.soldOut}
              onClick={() => onPick(opt)}
            >
              <span className="temp-pick-btn-label">{opt.label}</span>
              <span className="temp-pick-btn-price">
                {formatWon(opt.variant.price)}
              </span>
            </button>
          ))}
        </div>

        <div className="date-sheet-actions">
          <button
            type="button"
            className="btn btn-ghost"
            disabled={busy}
            onClick={onClose}
          >
            취소
          </button>
          {busy ? (
            <span className="muted" style={{ fontSize: '0.85rem' }}>
              주문 준비 중…
            </span>
          ) : null}
        </div>
      </div>
    </div>,
    document.body,
  )
}
