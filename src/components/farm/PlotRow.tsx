import { useEffect, useMemo, useState } from "react";
import { Clock, Droplets, Leaf, Scissors, Heart } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import { fmtAmount, seedToUsdt } from "@/lib/currency";
import { CropArt } from "./CropArt";
import {
  CARE_META,
  EVENT_META,
  STAGE_LABELS,
  formatRemaining,
  growthStage,
  seedPlanName,
  type CareAction,
  type EventCode,
} from "@/lib/farm-game";
import type { Plot } from "@/lib/farm-game.functions";

const ICONS: Record<CareAction, typeof Droplets> = {
  water: Droplets,
  fertilize: Leaf,
  weed: Scissors,
};

function useNow(intervalMs = 1000) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), intervalMs);
    return () => clearInterval(t);
  }, [intervalMs]);
  return now;
}

export function PlotRow({
  plot,
  rate,
  index,
  onCare,
  onReap,
  busy,
  splashing,
}: {
  plot: Plot;
  rate: number;
  index: number;
  onCare: (action: CareAction) => void;
  onReap: () => void;
  busy: boolean;
  splashing: CareAction | null;
}) {
  const now = useNow();
  const { cycle, state, lastCare } = plot;

  const maturesMs = new Date(cycle.matures_at).getTime();
  const remaining = Math.max(0, maturesMs - now);
  const matured = remaining === 0 && cycle.status !== "reaped" && cycle.status !== "cancelled";
  const stage = useMemo(() => growthStage(cycle.started_at, cycle.matures_at, now), [cycle.started_at, cycle.matures_at, now]);

  const total = cycle.duration_hours * 3600 * 1000;
  const pct = total > 0 ? Math.min(100, Math.round(((total - remaining) / total) * 100)) : 100;

  const amount = Number(cycle.amount);
  const reward = (amount * cycle.reward_bps) / 10000;
  const health = state?.health ?? 80;

  const eventCode = state?.event_code as EventCode | null | undefined;
  const eventActive = Boolean(eventCode && (!state?.event_expires_at || new Date(state.event_expires_at).getTime() > now));
  const event = eventActive && eventCode ? EVENT_META[eventCode] : null;

  return (
    <article className="rounded-2xl border border-border/60 bg-card/70 p-4 transition hover:border-primary/40">
      <div className="grid grid-cols-[auto_minmax(0,1fr)] gap-3">
        <CropArt stage={stage} health={health} watering={splashing === "water"} />

        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-sm font-semibold">Plot {index + 1}</span>
            <Badge variant={matured ? "default" : "outline"} className="text-[10px]">
              {matured ? "Ready to harvest" : STAGE_LABELS[stage]}
            </Badge>
            <span className="text-[11px] text-muted-foreground">
              {seedPlanName(cycle.duration_hours)} · +{(cycle.reward_bps / 100).toFixed(2)}%
            </span>
          </div>

          <p className="mt-1 truncate text-sm">
            <span className="font-medium">{fmtAmount(amount)} Seed</span>
            <span className="ml-1 text-[11px] text-muted-foreground">≈ {fmtAmount(seedToUsdt(amount, rate))} USDT</span>
          </p>

          <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-muted">
            <div className="h-full rounded-full bg-primary transition-all" style={{ width: `${pct}%` }} />
          </div>

          <div className="mt-1.5 flex flex-wrap items-center justify-between gap-x-3 gap-y-1 text-[11px] text-muted-foreground">
            <span className="inline-flex items-center gap-1">
              <Clock className="h-3 w-3" /> {formatRemaining(remaining)}
            </span>
            <span className="inline-flex items-center gap-1">
              <Heart className={cn("h-3 w-3", health < 45 ? "text-destructive" : "text-primary")} />
              {health}% health
            </span>
            <span>Reward: {fmtAmount(reward)} Seed</span>
          </div>
        </div>
      </div>

      {event && (
        <div
          className={cn(
            "mt-3 flex items-start gap-2 rounded-xl border px-3 py-2 text-xs",
            event.harmful ? "border-destructive/40 bg-destructive/10" : "border-gold/40 bg-gold/10",
          )}
        >
          <span aria-hidden="true" className="text-base leading-none">
            {event.emoji}
          </span>
          <span className="min-w-0">
            <span className="font-medium">{event.label}</span>
            <span className="block text-muted-foreground">{event.blurb}</span>
          </span>
        </div>
      )}

      <div className="mt-3 grid grid-cols-3 gap-2">
        {(Object.keys(CARE_META) as CareAction[]).map((action) => {
          const meta = CARE_META[action];
          const Icon = ICONS[action];
          const last = lastCare[action] ? new Date(lastCare[action] as string).getTime() : 0;
          const readyAt = last ? last + meta.cooldownHours * 3600 * 1000 : 0;
          const cooling = readyAt > now;
          const isCure = event?.cure === action;
          return (
            <Button
              key={action}
              type="button"
              size="sm"
              variant={isCure ? "default" : "outline"}
              className={cn("h-auto flex-col gap-0.5 py-2", isCure && "ring-1 ring-primary")}
              disabled={cooling || busy || cycle.status === "reaped"}
              onClick={() => onCare(action)}
            >
              <Icon className="h-4 w-4" />
              <span className="text-[11px]">{cooling ? formatRemaining(readyAt - now) : meta.label}</span>
            </Button>
          );
        })}
      </div>

      {matured && (
        <Button className="mt-2 w-full" onClick={onReap} disabled={busy}>
          Harvest plot
        </Button>
      )}
    </article>
  );
}
