import { useEffect, useId } from 'react'
import { createPortal } from 'react-dom'
import { MenuThumb } from './MenuThumb'

export type PreviewImage = {
  /** Optional — missing/broken src shows CSS “준비 중” placeholder */
  src?: string | null
  alt?: string
  /** Menu name / primary title under the image */
  caption?: string
  /** Secondary lines under caption (반찬, 원산지, 영양 등) */
  detail?: string
}

type Props = {
  image: PreviewImage | null
  onClose: () => void
}

/** Fullscreen meal/goods image preview. Tap anywhere (or Escape) to close. */
export function ImagePreview({ image, onClose }: Props) {
  const titleId = useId()

  useEffect(() => {
    if (!image) return
    const gap = window.innerWidth - document.documentElement.clientWidth
    document.documentElement.style.setProperty(
      '--scroll-lock-gap',
      `${Math.max(0, gap)}px`,
    )
    document.body.classList.add('is-scroll-lock')

    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => {
      document.body.classList.remove('is-scroll-lock')
      document.documentElement.style.removeProperty('--scroll-lock-gap')
      window.removeEventListener('keydown', onKey)
    }
  }, [image, onClose])

  if (!image || typeof document === 'undefined') return null

  const src = image.src?.trim() || null
  const alt = image.alt || image.caption || '메뉴 사진'

  return createPortal(
    <div
      className="img-preview"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      onClick={onClose}
    >
      <figure className="img-preview-figure">
        <MenuThumb
          src={src}
          alt={alt}
          variant="block"
          className="img-preview-img"
          loading="eager"
        />
        {(image.caption || image.alt || image.detail) && (
          <figcaption id={titleId} className="img-preview-caption">
            {(image.caption || image.alt) && (
              <span className="img-preview-title">
                {image.caption || image.alt}
              </span>
            )}
            {image.detail?.trim() ? (
              <span className="img-preview-detail">{image.detail.trim()}</span>
            ) : null}
          </figcaption>
        )}
      </figure>
    </div>,
    document.body,
  )
}
