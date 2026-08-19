import { Lock, Trophy } from "lucide-react";
import { cn } from "@/lib/utils";
import type { AchievementView } from "@/lib/farm-game.functions";

const EMOJI: Record<string, string> = {
  sprout: "🌱",
  wheat: "🌾",
  hand: "🤲",
  sparkles: "✨",
  flame: "🔥",
  crown: "👑",
  trophy: "🏆",
  star: "⭐",
  medal: "🎖️",
};

export function TrophyGrid({ achievements }: { achievements: AchievementView[] }) {
  const unlocked = achievements.filter((a) => a.unlockedAt).length;

  return (
    <section className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="flex items-center gap-2 text-sm font-semibold">
          <Trophy className="h-4 w-4 text-gold" /> Trophies
        </h2>
        <span className="text-xs text-muted-foreground">
          {unlocked} / {achievements.length} unlocked
        </span>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        {achievements.map((a) => {
          const on = Boolean(a.unlockedAt);
          return (
            <div
              key={a.code}
              className={cn(
                "rounded-2xl border p-3 text-center transition",
                on ? "border-gold/40 bg-gold/10" : "border-border/60 bg-card/60 opacity-70",
              )}
            >
              <div className="mx-auto grid h-11 w-11 place-items-center rounded-full bg-background/40 text-xl">
                {on ? (EMOJI[a.icon] ?? "🏆") : <Lock className="h-4 w-4 text-muted-foreground" />}
              </div>
              <p className="mt-2 text-xs font-semibold">{a.label}</p>
              <p className="mt-0.5 text-[11px] text-muted-foreground">{a.description}</p>
            </div>
          );
        })}
      </div>
    </section>
  );
}
