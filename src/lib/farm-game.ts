// Pure, client-safe helpers for the farm game layer (no I/O).

export type CareAction = "water" | "fertilize" | "weed";

export const CARE_META: Record<
  CareAction,
  { label: string; verb: string; cooldownHours: number; xp: number; emoji: string }
> = {
  water: { label: "Water", verb: "Watered", cooldownHours: 6, xp: 10, emoji: "💧" },
  weed: { label: "Weed", verb: "Weeded", cooldownHours: 12, xp: 15, emoji: "🌾" },
  fertilize: { label: "Feed", verb: "Fertilized", cooldownHours: 24, xp: 20, emoji: "🧺" },
};

export type EventCode = "drought" | "aphids" | "storm" | "frost" | "sunny";

export const EVENT_META: Record<
  EventCode,
  { label: string; blurb: string; emoji: string; harmful: boolean; cure: CareAction | null }
> = {
  drought: { label: "Drought", blurb: "The soil is cracking — water this plot.", emoji: "🥵", harmful: true, cure: "water" },
  aphids: { label: "Aphids", blurb: "Pests on the leaves — clear them out.", emoji: "🐛", harmful: true, cure: "weed" },
  storm: { label: "Storm damage", blurb: "Wind battered the rows — feed the soil.", emoji: "⛈️", harmful: true, cure: "fertilize" },
  frost: { label: "Cold snap", blurb: "Frost on the shoots — feed the soil.", emoji: "❄️", harmful: true, cure: "fertilize" },
  sunny: { label: "Golden sun", blurb: "Perfect weather — care now for bonus XP.", emoji: "☀️", harmful: false, cure: null },
};

/** XP required to reach a level: 100 * (level-1)^2 */
export function xpForLevel(level: number): number {
  return 100 * Math.pow(Math.max(1, level) - 1, 2);
}

export function levelProgress(xp: number, level: number) {
  const floor = xpForLevel(level);
  const next = xpForLevel(level + 1);
  const span = Math.max(1, next - floor);
  return {
    into: Math.max(0, xp - floor),
    span,
    next,
    pct: Math.min(100, Math.max(0, Math.round(((xp - floor) / span) * 100))),
  };
}

/** 0..4 growth stage from elapsed fraction of the cycle. */
export function growthStage(startedAt: string, maturesAt: string, now = Date.now()): number {
  const s = new Date(startedAt).getTime();
  const e = new Date(maturesAt).getTime();
  if (!Number.isFinite(s) || !Number.isFinite(e) || e <= s) return 4;
  const f = (now - s) / (e - s);
  if (f >= 1) return 4;
  if (f >= 0.75) return 3;
  if (f >= 0.45) return 2;
  if (f >= 0.15) return 1;
  return 0;
}

export const STAGE_LABELS = ["Seeded", "Sprouting", "Leafing", "Budding", "Ripe"];

export function formatRemaining(ms: number): string {
  if (ms <= 0) return "Ready";
  const s = Math.floor(ms / 1000);
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (d > 0) return `${d}d ${h}h ${m}m`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m ${sec}s`;
}

export function seedPlanName(hours: number): string {
  const days = Math.round(hours / 24);
  return days <= 1 ? "1 Day" : `${days} Days`;
}
