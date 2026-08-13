// Best-effort, per-instance throttle for unauthenticated endpoints.
//
// Server instances are stateless and may be recycled, so this is a speed bump
// against bulk enumeration of public lookups — not a hard guarantee. Keep the
// window short and the bucket small so memory stays bounded.

type Bucket = { count: number; resetAt: number };

const buckets = new Map<string, Bucket>();
const MAX_KEYS = 5_000;

export type ThrottleResult = { allowed: boolean; retryAfterMs: number };

/**
 * Consume one token for `key`. Allows at most `limit` calls per `windowMs`.
 */
export function throttle(key: string, limit: number, windowMs: number): ThrottleResult {
  const now = Date.now();

  // Opportunistic sweep of expired buckets; hard-cap the map as a backstop.
  if (buckets.size > MAX_KEYS) {
    for (const [k, b] of buckets) if (b.resetAt <= now) buckets.delete(k);
    if (buckets.size > MAX_KEYS) buckets.clear();
  }

  const existing = buckets.get(key);
  if (!existing || existing.resetAt <= now) {
    buckets.set(key, { count: 1, resetAt: now + windowMs });
    return { allowed: true, retryAfterMs: 0 };
  }
  if (existing.count >= limit) {
    return { allowed: false, retryAfterMs: existing.resetAt - now };
  }
  existing.count += 1;
  return { allowed: true, retryAfterMs: 0 };
}

/** Caller IP from common proxy headers, falling back to a shared bucket. */
export function clientIp(request: Request | undefined): string {
  const h = request?.headers;
  if (!h) return "unknown";
  const forwarded = h.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0]!.trim();
  return h.get("cf-connecting-ip") ?? h.get("x-real-ip") ?? "unknown";
}
