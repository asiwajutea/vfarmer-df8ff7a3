import { Flame, Trophy } from "lucide-react";
import { cn } from "@/lib/utils";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import type { LeaderRow } from "@/lib/farm-game.functions";

export function LeaderboardList({ rows, loading }: { rows: LeaderRow[]; loading: boolean }) {
  if (loading) {
    return (
      <div className="space-y-2">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="skeleton h-14 rounded-2xl" />
        ))}
      </div>
    );
  }

  if (!rows.length) {
    return (
      <p className="rounded-2xl border border-dashed border-border/60 p-8 text-center text-sm text-muted-foreground">
        No farmers on the board yet — plant and care to claim the top spot.
      </p>
    );
  }

  const me = rows.find((r) => r.isMe);

  return (
    <section className="space-y-3">
      <h2 className="flex items-center gap-2 text-sm font-semibold">
        <Trophy className="h-4 w-4 text-gold" /> Top farmers
      </h2>

      <div className="space-y-2">
        {rows.map((r) => (
          <Row key={r.user_id} row={r} />
        ))}
      </div>

      {me && (
        <div className="sticky bottom-2">
          <div className="rounded-2xl border border-primary/50 bg-background/95 p-1 shadow-[var(--shadow-elegant)] backdrop-blur">
            <Row row={me} />
          </div>
        </div>
      )}
    </section>
  );
}

function Row({ row }: { row: LeaderRow }) {
  return (
    <div
      className={cn(
        "grid grid-cols-[auto_auto_minmax(0,1fr)_auto] items-center gap-3 rounded-2xl border px-3 py-2.5",
        row.isMe ? "border-primary/50 bg-primary/10" : "border-border/60 bg-card/70",
      )}
    >
      <span className="w-6 shrink-0 text-center text-sm font-bold tabular-nums text-muted-foreground">{row.rank}</span>
      <Avatar className="h-9 w-9 shrink-0">
        <AvatarImage src={row.avatar_url ?? undefined} alt="" />
        <AvatarFallback>{row.display_name.slice(0, 2).toUpperCase()}</AvatarFallback>
      </Avatar>
      <div className="min-w-0">
        <p className="truncate text-sm font-medium">
          {row.display_name}
          {row.isMe && <span className="ml-1 text-[11px] text-primary">(you)</span>}
        </p>
        <p className="truncate text-[11px] text-muted-foreground">
          Level {row.level} · {row.badges} badges
        </p>
      </div>
      <div className="shrink-0 text-right">
        <p className="text-sm font-semibold tabular-nums">{row.xp.toLocaleString()} XP</p>
        <p className="inline-flex items-center gap-1 text-[11px] text-muted-foreground">
          <Flame className="h-3 w-3" /> {row.streak_count}d
        </p>
      </div>
    </div>
  );
}
