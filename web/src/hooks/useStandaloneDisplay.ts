import { useEffect, useState } from 'react'
import {
  isStandaloneDisplay,
  subscribeStandaloneDisplay,
} from '../lib/display-mode'

/** True when running as installed web app (not mobile Chrome tab). */
export function useStandaloneDisplay(): boolean {
  const [standalone, setStandalone] = useState(() =>
    typeof window !== 'undefined' ? isStandaloneDisplay() : false,
  )

  useEffect(() => {
    setStandalone(isStandaloneDisplay())
    return subscribeStandaloneDisplay(setStandalone)
  }, [])

  return standalone
}
