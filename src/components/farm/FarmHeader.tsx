import { Flame, Sparkles, Wallet as WalletIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { levelProgress } from "@/lib/farm-game";
import { fmtAmount, seedToUsdt } from "@/lib/currency";

export function FarmHeader({
  xp,
  level,
  streak,
  checkedInToday,
  balance,
  rate,
  onCheckIn,
  checkingIn,
}: {
  xp: number;
  level: number;
  streak: number;
  checkedInToday: boolean;
  balance: number;
  rate: number;
  onCheckIn: () => void;
  checkingIn: boolean;
}) {
  const prog = levelProgress(xp, level);
  const circumference = 2 * Math.PI * 26;

  return (
    <section className="rounded-2xl border border-border/60 bg-card/70 p-4 shadow-[var(--shadow-elegant)]">
      <div className="grid grid-cols-[auto_minmax(0,1fr)] items-center gap-4">
        <div className="relative h-16 w-16 shrink-0">
          <svg viewBox="0 0 64 64" className="h-full w-full -rotate-90">
            <circle cx="32" cy="32" r="26" className="fill-none stroke-muted" strokeWidth="6" />
            <circle
              cx="32"
              cy="32"
              r="26"
              className="fill-none stroke-primary transition-all duration-700"
              strokeWidth="6"
              strokeLinecap="round"
              strokeDasharray={circumference}
              strokeDashoffset={circumference * (1 - prog.pct / 100)}
            />
          </svg>
          <span className="absolute inset-0 grid place-items-center text-sm font-bold">{level}</span>
        </div>

        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <h2 className="truncate text-base font-semibold">Farmer level {level}</h2>
            <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-gold/15 px-2 py-0.5 text-[11px] font-medium text-gold">
              <Flame className="h-3 w-3" /> {streak}d streak
            </span>
          </div>
          <p className="mt-1 text-xs text-muted-foreground">
            {prog.into} / {prog.span} XP to level {level + 1}
          </p>
          <div className="mt-1.5 h-1.5 w-full overflow-hidden rounded-full bg-muted">
            <div className="h-full rounded-full bg-primary transition-all duration-700" style={{ width: `${prog.pct}%` }} />
          </div>
        </div>
      </div>

      <div className="mt-4 grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3">
        <div className="min-w-0 rounded-xl bg-muted/40 px-3 py-2">
          <p className="flex items-center gap-1.5 text-[11px] text-muted-foreground">
            <WalletIcon className="h-3 w-3 shrink-0" /> Farming balance
          </p>
          <p className="truncate text-sm font-semibold">
            {fmtAmount(balance)} Seed
            <span className="ml-1 text-[11px] font-normal text-muted-foreground">
              ≈ {fmtAmount(seedToUsdt(balance, rate))} USDT
            </span>
          </p>
        </div>
        <Button size="sm" className="shrink-0" onClick={onCheckIn} disabled={checkedInToday || checkingIn}>
          <Sparkles className="mr-1 h-4 w-4" />
          {checkedInToday ? "Checked in" : checkingIn ? "…" : "Check in"}
        </Button>
      </div>
    </section>
  );
}
