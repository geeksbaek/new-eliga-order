import { useNavigate } from 'react-router-dom'
import { IconChevronLeft } from './Icons'

type Props = {
  /** Fallback path when history is empty */
  fallbackTo?: string
  label?: string
  className?: string
  onClick?: () => void
}

export function BackButton({
  fallbackTo = '/',
  label = '뒤로',
  className = '',
  onClick,
}: Props) {
  const navigate = useNavigate()

  function handleClick() {
    if (onClick) {
      onClick()
      return
    }
    if (window.history.length > 1) {
      navigate(-1)
    } else {
      navigate(fallbackTo)
    }
  }

  return (
    <button
      type="button"
      className={`back-btn ${className}`.trim()}
      onClick={handleClick}
      aria-label={label}
    >
      <span className="back-btn-icon" aria-hidden>
        <IconChevronLeft size={18} />
      </span>
      <span className="back-btn-label">{label}</span>
    </button>
  )
}
