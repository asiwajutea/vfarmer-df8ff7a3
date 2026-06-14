import { X, Download, Sprout } from "lucide-react";

interface Props {
  onInstall: () => void;
  onDismiss: () => void;
}

/**
 * Non-intrusive install banner shown at the bottom of the screen.
 * Only rendered when the browser fires `beforeinstallprompt` (Chrome/Edge/Android).
 * Safari users installing via "Add to Home Screen" are handled by the browser natively.
 *
 * Best-practice notes:
 * - Shown at the bottom so it doesn't obscure main content
 * - Never shown immediately on load — the hook only captures the event when the
 *   browser decides the app meets installability criteria
 * - Dismissible, and dismissed state persists for the session
 */
export function InstallPrompt({ onInstall, onDismiss }: Props) {
  return (
    <div
      role="dialog"
      aria-label="Install VFarmers app"
      className="fixed bottom-4 left-4 right-4 z-50 mx-auto max-w-sm animate-in slide-in-from-bottom-4 duration-300"
    >
      <div className="glass flex items-center gap-3 rounded-2xl border border-primary/20 bg-card/95 p-4 shadow-elegant backdrop-blur-md">
        {/* App icon */}
        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-primary/15 text-primary">
          <Sprout className="h-5 w-5" />
        </div>

        {/* Text */}
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold leading-tight">Install VFarmers</p>
          <p className="mt-0.5 text-xs text-muted-foreground">
            Add to your home screen for a faster, app-like experience.
          </p>
        </div>

        {/* Actions */}
        <div className="flex shrink-0 items-center gap-1.5">
          <button
            type="button"
            onClick={onInstall}
            className="inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-primary to-accent px-3 py-1.5 text-xs font-semibold text-primary-foreground shadow-glow transition-transform hover:scale-[1.03]"
            aria-label="Install app"
          >
            <Download className="h-3.5 w-3.5" />
            Install
          </button>
          <button
            type="button"
            onClick={onDismiss}
            aria-label="Dismiss install prompt"
            className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}
