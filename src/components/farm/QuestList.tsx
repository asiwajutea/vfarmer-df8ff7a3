import { CheckCircle2, Circle } from "lucide-react";
import { cn } from "@/lib/utils";
import type { QuestView } from "@/lib/farm-game.functions";

export function QuestList({ quests }: { quests: QuestView[] }) {
  const done = quests.filter((q) => q.completed).length;

  return (
    <section className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold">Today&apos;s quests</h2>
        <span className="text-xs text-muted-foreground">
          {done} / {quests.length} complete
        </span>
      </div>

      {quests.map((q) => {
        const pct = Math.min(100, Math.round((q.progress / Math.max(1, q.target)) * 100));
        return (
          <div
            key={q.code}
            className={cn(
              "rounded-2xl border p-3.5",
              q.completed ? "border-primary/40 bg-primary/5" : "border-border/60 bg-card/70",
            )}
          >
            <div className="grid grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3">
              {q.completed ? (
                <CheckCircle2 className="h-5 w-5 shrink-0 text-primary" />
              ) : (
                <Circle className="h-5 w-5 shrink-0 text-muted-foreground" />
              )}
              <div className="min-w-0">
                <p className="truncate text-sm font-medium">{q.label}</p>
                <p className="truncate text-[11px] text-muted-foreground">{q.description}</p>
              </div>
              <span className="shrink-0 rounded-full bg-gold/15 px-2 py-0.5 text-[11px] font-medium text-gold">
                +{q.xp} XP
              </span>
            </div>
            <div className="mt-2.5 h-1.5 w-full overflow-hidden rounded-full bg-muted">
              <div className="h-full rounded-full bg-primary transition-all" style={{ width: `${pct}%` }} />
            </div>
            <p className="mt-1 text-right text-[11px] text-muted-foreground">
              {Math.min(q.progress, q.target)} / {q.target}
            </p>
          </div>
        );
      })}
    </section>
  );
}
