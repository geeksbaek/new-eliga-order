/**
 * App icons — thin wrappers around lucide-react for consistent size / stroke.
 */
import type { LucideIcon, LucideProps } from 'lucide-react'
import {
  Bell,
  ChevronLeft,
  ChevronRight,
  Coffee,
  Home,
  Plus,
  Receipt,
  Settings,
  ShoppingBag,
  Star,
  Trash2,
  Utensils,
} from 'lucide-react'

export type IconProps = {
  size?: number
  className?: string
  'aria-hidden'?: boolean | 'true' | 'false'
  /** Filled variant (e.g. favorited star) */
  filled?: boolean
  strokeWidth?: number
}

function lucide(Icon: LucideIcon, defaults?: Partial<LucideProps>) {
  return function AppIcon({
    size = 22,
    className,
    filled = false,
    strokeWidth = 1.75,
    ...rest
  }: IconProps) {
    return (
      <Icon
        size={size}
        className={className}
        strokeWidth={strokeWidth}
        fill={filled ? 'currentColor' : 'none'}
        aria-hidden={rest['aria-hidden'] ?? true}
        {...defaults}
      />
    )
  }
}

export const IconHome = lucide(Home)
export const IconUtensils = lucide(Utensils)
export const IconCup = lucide(Coffee)
export const IconReceipt = lucide(Receipt)
export const IconBag = lucide(ShoppingBag)
export const IconChevronRight = lucide(ChevronRight)
export const IconChevronLeft = lucide(ChevronLeft)
export const IconPlus = lucide(Plus)
export const IconSettings = lucide(Settings)
export const IconBell = lucide(Bell)
export const IconStar = lucide(Star)
export const IconTrash = lucide(Trash2)
