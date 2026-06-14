import { useEffect, useState } from "react";

interface BeforeInstallPromptEvent extends Event {
  readonly platforms: string[];
  readonly userChoice: Promise<{ outcome: "accepted" | "dismissed"; platform: string }>;
  prompt(): Promise<void>;
}

/**
 * Registers the service worker, tracks online/offline state, and captures the
 * browser's install prompt so we can show it at the right moment.
 *
 * Online detection: we always start as `true` (assume online) and only update
 * after the effect fires on the client. This prevents SSR/hydration mismatches
 * that cause the offline banner to flash on page load.
 */
export function usePwa() {
  // Always start true — updated after mount to avoid SSR mismatch.
  const [isOnline, setIsOnline] = useState(true);
  const [installPrompt, setInstallPrompt] = useState<BeforeInstallPromptEvent | null>(null);
  const [isInstalled, setIsInstalled] = useState(false);
  const [installDismissed, setInstallDismissed] = useState(false);

  useEffect(() => {
    // Sync real online state after hydration
    setIsOnline(navigator.onLine);

    // Register service worker
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker
        .register("/sw.js", { scope: "/" })
        .catch((err) => console.warn("[SW] Registration failed:", err));
    }

    // Check if already installed (standalone mode or iOS standalone)
    const alreadyInstalled =
      window.matchMedia("(display-mode: standalone)").matches ||
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (navigator as any).standalone === true;
    if (alreadyInstalled) setIsInstalled(true);

    // Capture the install prompt — browser fires this before showing its own UI
    const handleBeforeInstall = (e: Event) => {
      e.preventDefault(); // Suppress the default mini-infobar
      setInstallPrompt(e as BeforeInstallPromptEvent);
    };

    // If the user installs via our prompt or the browser's UI, mark as installed
    const handleAppInstalled = () => {
      setIsInstalled(true);
      setInstallPrompt(null);
    };

    const handleOnline = () => setIsOnline(true);
    const handleOffline = () => setIsOnline(false);

    window.addEventListener("beforeinstallprompt", handleBeforeInstall);
    window.addEventListener("appinstalled", handleAppInstalled);
    window.addEventListener("online", handleOnline);
    window.addEventListener("offline", handleOffline);

    return () => {
      window.removeEventListener("beforeinstallprompt", handleBeforeInstall);
      window.removeEventListener("appinstalled", handleAppInstalled);
      window.removeEventListener("online", handleOnline);
      window.removeEventListener("offline", handleOffline);
    };
  }, []);

  const triggerInstall = async () => {
    if (!installPrompt) return;
    await installPrompt.prompt();
    const { outcome } = await installPrompt.userChoice;
    if (outcome === "accepted") {
      setIsInstalled(true);
    }
    setInstallPrompt(null);
  };

  const dismissInstall = () => {
    setInstallDismissed(true);
    setInstallPrompt(null);
  };

  // Show the install banner only when:
  // - browser fired beforeinstallprompt (app is installable)
  // - not already installed
  // - user hasn't dismissed it this session
  const showInstallPrompt = !!installPrompt && !isInstalled && !installDismissed;

  return { isOnline, showInstallPrompt, triggerInstall, dismissInstall, isInstalled };
}
