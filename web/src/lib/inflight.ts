/**
 * Share in-flight promises so concurrent callers hit the network once.
 * Keyed by string (e.g. "cafe:menu:5:all").
 */

const pending = new Map<string, Promise<unknown>>()

export function inflight<T>(key: string, run: () => Promise<T>): Promise<T> {
  const existing = pending.get(key)
  if (existing) return existing as Promise<T>

  const promise = run().finally(() => {
    if (pending.get(key) === promise) pending.delete(key)
  })
  pending.set(key, promise)
  return promise
}
