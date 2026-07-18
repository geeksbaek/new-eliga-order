import { useEffect, useState } from 'react'
import { isImageWarm, markImageWarm } from '../lib/image-warm'
import { IconUtensils } from './Icons'

type Props = {
  src?: string | null
  alt?: string
  width?: number
  height?: number
  loading?: 'lazy' | 'eager'
  decoding?: 'async' | 'sync' | 'auto'
  className?: string
  /**
   * inline — list thumbs (compact label)
   * block — hero / preview (icon + label)
   */
  variant?: 'inline' | 'block'
}

/** Real photo when available; otherwise CSS “준비 중” placeholder (no static image). */
export function MenuThumb({
  src,
  alt = '',
  width,
  height,
  loading,
  decoding,
  className,
  variant = 'inline',
}: Props) {
  const url = src?.trim() || ''
  const [failed, setFailed] = useState(false)
  const warm = isImageWarm(url)
  // Prefer eager/sync for warm list thumbs so back-navigation does not blank.
  const loadMode =
    loading ?? (variant === 'inline' && warm ? 'eager' : 'lazy')
  const decodeMode =
    decoding ?? (variant === 'inline' && warm ? 'sync' : 'async')

  useEffect(() => {
    setFailed(false)
  }, [url])

  if (!url || failed) {
    return (
      <span
        className={[
          'menu-ph',
          variant === 'block' ? 'menu-ph--block' : 'menu-ph--inline',
        ].join(' ')}
        role="img"
        aria-label={alt || '이미지 준비 중'}
      >
        {variant === 'block' ? (
          <span className="menu-ph-icon" aria-hidden>
            <IconUtensils size={32} />
          </span>
        ) : null}
        <span className="menu-ph-label">준비 중</span>
      </span>
    )
  }

  return (
    <img
      src={url}
      alt={alt}
      width={width}
      height={height}
      loading={loadMode}
      decoding={decodeMode}
      // Browser may still re-fetch if missing cache; fetchpriority helps list
      fetchPriority={loadMode === 'eager' ? 'high' : 'auto'}
      className={className}
      onLoad={() => markImageWarm(url)}
      onError={() => setFailed(true)}
    />
  )
}
