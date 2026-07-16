import { useEffect, useId, useMemo, useState } from 'react'
import { createPortal } from 'react-dom'
import { formatWon } from '../lib/format'
import { unitPriceWithOptions } from '../lib/cart-math'
import {
  defaultSelections,
  isExclusiveMultiGroup,
  selectionsToOptions,
} from '../lib/menu-options'
import { classifyTemp } from '../lib/temp-variants'
import type {
  GoodsOption,
  GoodsVariant,
  MenuDetail,
  SelectedOption,
} from '../lib/types'

type Props = {
  open: boolean
  menuName: string
  detail: MenuDetail
  /** Prefer list-row goodsId when picking the initial variant */
  preferredGoodsId?: number | null
  busy?: boolean
  willReplaceCart?: boolean
  onConfirm: (variant: GoodsVariant, options: SelectedOption[]) => void
  onClose: () => void
}

function pickInitialVariant(
  detail: MenuDetail,
  preferredGoodsId?: number | null,
): GoodsVariant | null {
  const avail = detail.variants.filter((v) => !v.soldOut)
  const pool = avail.length ? avail : detail.variants
  if (!pool.length) return null
  if (preferredGoodsId != null) {
    const hit = pool.find((v) => v.goodsId === preferredGoodsId)
    if (hit) return hit
  }
  // Prefer ICE when both exist (common cafe default); else first available
  const ice = pool.find((v) => classifyTemp(v) === 'ice')
  return ice ?? pool[0]
}

function missingRequiredLabels(
  variant: GoodsVariant,
  selected: Record<number, number[]>,
): string[] {
  const missing: string[] = []
  for (const opt of variant.options) {
    if (opt.multiSelect) continue
    if (!(selected[opt.optionId] ?? []).length) missing.push(opt.name)
  }
  return missing
}

/**
 * Bottom sheet for isolated quick order: variant (ICE/HOT/…) + all goods options.
 */
export function QuickOrderSheet({
  open,
  menuName,
  detail,
  preferredGoodsId = null,
  busy = false,
  willReplaceCart = false,
  onConfirm,
  onClose,
}: Props) {
  const titleId = useId()
  const [variantId, setVariantId] = useState<number | null>(null)
  const [selected, setSelected] = useState<Record<number, number[]>>({})

  useEffect(() => {
    if (!open) return
    const v = pickInitialVariant(detail, preferredGoodsId)
    setVariantId(v?.goodsId ?? null)
    setSelected(v ? defaultSelections(v) : {})
  }, [open, detail, preferredGoodsId])

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

  const variant =
    detail.variants.find((v) => v.goodsId === variantId) ?? null

  const selectedOptions = useMemo(() => {
    if (!variant) return [] as SelectedOption[]
    return selectionsToOptions(variant, selected)
  }, [variant, selected])

  const unitPrice = variant
    ? unitPriceWithOptions(variant.price, variant.options, selectedOptions)
    : 0

  const missing = variant ? missingRequiredLabels(variant, selected) : []
  const canSubmit =
    variant != null && !variant.soldOut && missing.length === 0 && !busy

  function selectVariant(v: GoodsVariant) {
    if (v.soldOut || busy) return
    setVariantId(v.goodsId)
    setSelected(defaultSelections(v))
  }

  function toggleOption(opt: GoodsOption, menuId: number) {
    if (busy) return
    setSelected((prev) => {
      const cur = prev[opt.optionId] ?? []
      if (opt.multiSelect) {
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
      return { ...prev, [opt.optionId]: [menuId] }
    })
  }

  if (!open || typeof document === 'undefined') return null

  const showVariants = detail.variants.length > 1

  return createPortal(
    <div
      className="date-sheet"
      role="presentation"
      onClick={() => {
        if (!busy) onClose()
      }}
    >
      <div
        className="date-sheet-panel quick-order-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="date-sheet-handle" aria-hidden />
        <header className="quick-order-head">
          <h2 id={titleId} className="date-sheet-title">
            바로 주문
          </h2>
          <p className="quick-order-sub">{menuName}</p>
          <p className="quick-order-hint">
            1잔만 주문합니다. 기존 장바구니 항목은 이 결제에 포함되지 않습니다.
            {willReplaceCart
              ? ' 주문 확인을 취소하면 이전 장바구니를 복구합니다.'
              : ''}
          </p>
        </header>

        <div className="quick-order-body">
          {showVariants && (
            <section className="quick-order-section">
              <h3 className="quick-order-section-title">온도 / 종류</h3>
              <div className="variant-row" role="group" aria-label="온도 / 종류">
                {detail.variants.map((v) => {
                  const kind = classifyTemp(v)
                  const extraClass =
                    kind === 'ice'
                      ? ' is-ice'
                      : kind === 'hot'
                        ? ' is-hot'
                        : ''
                  return (
                    <button
                      key={v.goodsId}
                      type="button"
                      className={`variant-btn${variantId === v.goodsId ? ' active' : ''}${extraClass}`}
                      disabled={busy || v.soldOut}
                      onClick={() => selectVariant(v)}
                    >
                      {v.displayName || v.name}
                      {v.soldOut ? ' (품절)' : ''}
                    </button>
                  )
                })}
              </div>
            </section>
          )}

          {variant &&
            variant.options.map((opt) => {
              const exclusive = isExclusiveMultiGroup(opt)
              return (
                <section
                  key={opt.optionId}
                  className="quick-order-section option-group"
                >
                  <h3 className="quick-order-section-title">
                    {opt.name}
                    {!opt.multiSelect || exclusive ? ' (택 1)' : ' (선택)'}
                  </h3>
                  <div
                    className="option-choices"
                    role="group"
                    aria-label={opt.name}
                  >
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
                          disabled={busy}
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
                </section>
              )
            })}

          {variant && variant.options.length === 0 && !showVariants && (
            <p className="quick-order-empty muted">추가 옵션이 없습니다.</p>
          )}
        </div>

        <div className="quick-order-footer">
          {missing.length > 0 && (
            <p className="quick-order-missing" role="status">
              필수 선택: {missing.join(', ')}
            </p>
          )}
          <div className="quick-order-total">
            <span className="muted">1잔</span>
            <strong>{formatWon(unitPrice)}</strong>
          </div>
          <div className="quick-order-actions">
            <button
              type="button"
              className="btn btn-ghost"
              disabled={busy}
              onClick={onClose}
            >
              취소
            </button>
            <button
              type="button"
              className="btn btn-primary"
              disabled={!canSubmit}
              onClick={() => {
                if (!variant || !canSubmit) return
                onConfirm(variant, selectedOptions)
              }}
            >
              {busy
                ? '준비 중…'
                : missing.length
                  ? '옵션을 선택해 주세요'
                  : `${formatWon(unitPrice)} · 주문 확인`}
            </button>
          </div>
        </div>
      </div>
    </div>,
    document.body,
  )
}
