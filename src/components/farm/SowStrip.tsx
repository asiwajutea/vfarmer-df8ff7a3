import { useState } from "react";
import { Sprout } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";
import { fmtAmount, seedToUsdt } from "@/lib/currency";
import { seedPlanName } from "@/lib/farm-game";
import type { Booster } from "@/lib/farm.functions";

export function SowStrip({
  boosters,
  balance,
  rate,
  onPlant,
  planting,
}: {
  boosters: Booster[];
  balance: number;
  rate: number;
  onPlant: (boosterId: string, amount: number) => void;
  planting: boolean;
}) {
  const [boosterId, setBoosterId] = useState("");
  const [amount, setAmount] = useState("");

  const selected = boosters.find((b) => b.id === boosterId);
  const amt = Number(amount) || 0;
  const reward = selected ? (amt * selected.reward_bps) / 10000 : 0;
  const tooMuch = amt > balance;

  return (
    <section className="rounded-2xl border border-border/60 bg-card/70 p-4">
      <h2 className="flex items-center gap-2 text-sm font-semibold">
        <Sprout className="h-4 w-4 text-primary" /> Sow a seed
      </h2>

      <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-4">
        {boosters.map((b) => {
          const active = b.id === boosterId;
          return (
            <button
              key={b.id}
              type="button"
              onClick={() => setBoosterId(b.id)}
              aria-pressed={active}
              className={cn(
                "rounded-xl border px-3 py-2.5 text-left transition",
                active ? "border-primary bg-primary/10 ring-1 ring-primary" : "border-border/60 hover:border-primary/50",
              )}
            >
              <span className="block text-sm font-semibold">{seedPlanName(b.duration_hours)}</span>
              <span className="mt-0.5 block text-[11px] text-muted-foreground">{b.duration_hours}h cycle</span>
              <span className="mt-1 block text-xs font-medium text-primary">+{(b.reward_bps / 100).toFixed(2)}%</span>
            </button>
          );
        })}
      </div>

      <div className="mt-3 space-y-2">
        <Label htmlFor="sow-amount" className="text-xs">
          Amount (Seed)
        </Label>
        <Input
          id="sow-amount"
          type="number"
          inputMode="decimal"
          step="0.01"
          min="0"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="e.g. 100"
        />
        <div className="flex flex-wrap gap-1.5">
          {[0.25, 0.5, 1].map((f) => (
            <button
              key={f}
              type="button"
              onClick={() => setAmount((balance * f).toFixed(2))}
              className="rounded-full border border-border/60 px-2.5 py-1 text-[11px] text-muted-foreground transition hover:border-primary/60 hover:text-foreground"
            >
              {f === 1 ? "Max" : `${f * 100}%`}
            </button>
          ))}
        </div>
        {amt > 0 && (
          <p className="text-[11px] text-muted-foreground">
            ≈ {fmtAmount(seedToUsdt(amt, rate))} USDT
            {selected && (
              <>
                {" · "}reward at harvest{" "}
                <span className="font-medium text-foreground">{fmtAmount(reward)} Seed</span>
              </>
            )}
          </p>
        )}
        {tooMuch && <p className="text-[11px] text-destructive">More than your Farming balance.</p>}
      </div>

      <Button
        className="mt-3 w-full"
        disabled={!boosterId || amt <= 0 || tooMuch || planting}
        onClick={() => onPlant(boosterId, amt)}
      >
        {planting ? "Planting…" : "Plant seed"}
      </Button>
    </section>
  );
}
