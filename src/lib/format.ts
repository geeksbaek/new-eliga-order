/**
 * Response field helpers matching skill fmt.py conventions.
 * price = NORMAL - IDCARD (employee ID card discount).
 */

/** Always returns a string safe to render as React text (never {ko,en} object). */
export function localizeName(obj: unknown): string {
  if (obj == null) return ''
  if (typeof obj === 'string') return obj.trim()
  if (typeof obj === 'number' || typeof obj === 'boolean') return String(obj)
  if (typeof obj === 'object') {
    const rec = obj as Record<string, unknown>
    const ko = rec.ko
    const en = rec.en
    if (typeof ko === 'string' && ko.trim()) return ko.trim()
    if (typeof en === 'string' && en.trim()) return en.trim()
    // Nested name bags or unexpected shapes — never return the object itself
    if (ko != null) return localizeName(ko)
    if (en != null) return localizeName(en)
  }
  return ''
}

export interface PricePlan {
  payMethodType?: string
  price?: number
  optionPrice?: number
  [key: string]: unknown
}

/** goodsPricePlans → real pay amount (NORMAL minus IDCARD). */
export function calcPlanPrice(
  plans: PricePlan[] | null | undefined,
  key: 'price' | 'optionPrice' = 'price',
): number {
  if (!plans || plans.length === 0) return 0
  const normal = plans.find((p) => p.payMethodType === 'NORMAL')
  const disc = plans.find((p) => p.payMethodType === 'IDCARD')
  const n = Number(normal?.[key] ?? 0)
  const d = Number(disc?.[key] ?? 0)
  return Math.trunc(n - d)
}

export function formatWon(amount: number): string {
  return `₩${Math.max(0, Math.trunc(amount)).toLocaleString('ko-KR')}`
}

export function formatKcal(calorie: number | null | undefined): string {
  if (calorie == null || Number.isNaN(Number(calorie))) return ''
  return `${calorie} kcal`
}

export function todayISODate(d = new Date()): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

export function congestionLabel(type: string | null | undefined): string {
  switch (type) {
    case 'SMOOTH':
      return '여유'
    case 'NORMAL':
      return '보통'
    case 'CROWDED':
      return '혼잡'
    default:
      return type || ''
  }
}

export function orderStatusLabel(status: string | null | undefined): string {
  switch (status) {
    case 'ORDER_RECEPTION':
      return '접수'
    case 'WAITING_FOR_PICKUP':
      return '픽업 대기'
    case 'PICKUP_COMPLETE':
      return '완료'
    case 'ORDER_CANCEL':
      return '취소'
    default:
      return status || '알 수 없음'
  }
}
