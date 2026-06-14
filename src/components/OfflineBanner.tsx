import { WifiOff } from "lucide-react";

/**
 * Shown when the user is offline. Rendered at the top of every page.
 * Live data (balances, cycles, etc.) is unavailable — the cached shell still
 * loads so navigation works, but no fresh data will be fetched.
 */
export function OfflineBanner() {
  return (
    <div
      role="status"
      aria-live="polite"
      className="flex items-center justify-center gap-2.5 bg-amber-500/15 px-4 py-2.5 text-center text-sm text-amber-400 border-b border-amber-500/20"
    >
      <WifiOff className="h-4 w-4 shrink-0" />
      <span>
        You're offline. Pages are available from cache but live data (balances, cycles, etc.) can't
        be loaded until your connection is restored.
      </span>
    </div>
  );
}
