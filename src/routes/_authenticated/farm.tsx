import { createFileRoute } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Sprout, ListChecks, Trophy, Users, Info } from "lucide-react";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import { useSeedRate } from "@/components/wallet/RequestForm";
import { listBoosters, startCycleFn, reapCycleFn } from "@/lib/farm.functions";
import {
  getFarmOverview,
  careForPlot,
  dailyCheckin,
  getLeaderboard,
} from "@/lib/farm-game.functions";
import type { CareAction } from "@/lib/farm-game";
import { FarmHeader } from "@/components/farm/FarmHeader";
import { SowStrip } from "@/components/farm/SowStrip";
import { PlotRow } from "@/components/farm/PlotRow";
import { QuestList } from "@/components/farm/QuestList";
import { TrophyGrid } from "@/components/farm/TrophyGrid";
import { LeaderboardList } from "@/components/farm/LeaderboardList";

export const Route = createFileRoute("/_authenticated/farm")({
  head: () => ({
    meta: [
      { title: "My Farm · VFarmers" },
      {
        name: "description",
        content: "Sow seeds, water, feed and weed your plots, complete daily quests and climb the VFarmers leaderboard.",
      },
      { name: "robots", content: "noindex" },
    ],
  }),
  component: FarmPage,
});

type Tab = "farm" | "quests" | "trophies" | "board";

const TABS: { id: Tab; label: string; icon: typeof Sprout }[] = [
  { id: "farm", label: "Farm", icon: Sprout },
  { id: "quests", label: "Quests", icon: ListChecks },
  { id: "trophies", label: "Trophies", icon: Trophy },
  { id: "board", label: "Ranks", icon: Users },
];

function FarmPage() {
  const qc = useQueryClient();
  const [tab, setTab] = useState<Tab>("farm");
  const [splash, setSplash] = useState<{ cycleId: string; action: CareAction } | null>(null);

  const fnOverview = useServerFn(getFarmOverview);
  const fnBoosters = useServerFn(listBoosters);
  const fnLeaders = useServerFn(getLeaderboard);
  const fnCare = useServerFn(careForPlot);
  const fnCheckin = useServerFn(dailyCheckin);
  const fnStart = useServerFn(startCycleFn);
  const fnReap = useServerFn(reapCycleFn);

  const overviewQ = useQuery({
    queryKey: ["farm-overview"],
    queryFn: () => fnOverview({ data: undefined }),
    refetchInterval: 60_000,
  });
  const boostersQ = useQuery({ queryKey: ["boosters"], queryFn: () => fnBoosters() });
  const leadersQ = useQuery({ queryKey: ["farm-leaderboard"], queryFn: () => fnLeaders(), enabled: tab === "board" });
  const { data: rate = 1 } = useSeedRate();

  const refresh = () => {
    qc.invalidateQueries({ queryKey: ["farm-overview"] });
    qc.invalidateQueries({ queryKey: ["farm-leaderboard"] });
  };

  const careMut = useMutation({
    mutationFn: (vars: { cycleId: string; action: CareAction }) => fnCare({ data: vars }),
    onMutate: (vars) => setSplash(vars),
    onSuccess: (res, vars) => {
      toast.success(
        res.cured
          ? `Crisis handled! +${res.xp} XP`
          : `${vars.action === "water" ? "Watered" : vars.action === "weed" ? "Weeded" : "Fertilized"} · +${res.xp} XP`,
      );
      if (res.unlocked.length) toast.success(`New trophy unlocked! 🏆`);
      refresh();
    },
    onError: (e: Error) => toast.error(e.message || "Could not do that right now"),
    onSettled: () => setTimeout(() => setSplash(null), 900),
  });

  const checkinMut = useMutation({
    mutationFn: () => fnCheckin({ data: undefined }),
    onSuccess: (res) => {
      toast.success(`Day ${res.streak} streak · +${res.xp} XP`);
      refresh();
    },
    onError: (e: Error) => toast.error(e.message || "Check-in failed"),
  });

  const startMut = useMutation({
    mutationFn: (vars: { boosterId: string; amount: number }) => fnStart({ data: vars }),
    onSuccess: () => {
      toast.success("Seed planted 🌱");
      refresh();
    },
    onError: (e: Error) => toast.error(e.message || "Could not plant"),
  });

  const reapMut = useMutation({
    mutationFn: (cycleId: string) => fnReap({ data: { cycleId } }),
    onSuccess: () => {
      toast.success("Harvested! Seeds are back in your Farming wallet 🎉");
      refresh();
    },
    onError: (e: Error) => toast.error(e.message || "Could not harvest"),
  });

  const data = overviewQ.data;
  const busy = careMut.isPending || reapMut.isPending;

  return (
    <div className="mx-auto max-w-3xl px-4 pb-24 pt-6 sm:px-6">
      <div className="inline-flex items-center gap-2 rounded-full border border-primary/30 bg-primary/10 px-3 py-1 text-[11px] text-primary">
        <Sprout className="h-3.5 w-3.5" /> Your virtual farm
      </div>
      <h1 className="mt-2 text-2xl font-semibold tracking-tight sm:text-3xl">Farm</h1>
      <p className="mt-1 text-sm text-muted-foreground">
        Sow, tend and harvest. Caring for plots earns XP, streaks and trophies.
      </p>

      <div className="mt-5">
        {overviewQ.isLoading || !data ? (
          <div className="space-y-3">
            <div className="skeleton h-32 rounded-2xl" />
            <div className="skeleton h-44 rounded-2xl" />
            <div className="skeleton h-28 rounded-2xl" />
          </div>
        ) : (
          <>
            <FarmHeader
              xp={data.profile.xp}
              level={data.profile.level}
              streak={data.profile.streak}
              checkedInToday={data.profile.checkedInToday}
              balance={data.farmingBalance}
              rate={rate}
              onCheckIn={() => checkinMut.mutate()}
              checkingIn={checkinMut.isPending}
            />

            {/* Tabs */}
            <nav className="mt-4 grid grid-cols-4 gap-1 rounded-2xl border border-border/60 bg-card/60 p-1">
              {TABS.map((t) => {
                const Icon = t.icon;
                const active = tab === t.id;
                return (
                  <button
                    key={t.id}
                    type="button"
                    onClick={() => setTab(t.id)}
                    aria-current={active ? "page" : undefined}
                    className={cn(
                      "flex flex-col items-center gap-0.5 rounded-xl py-2 text-[11px] font-medium transition",
                      active ? "bg-primary/15 text-primary" : "text-muted-foreground hover:text-foreground",
                    )}
                  >
                    <Icon className="h-4 w-4" />
                    {t.label}
                  </button>
                );
              })}
            </nav>

            <div className="mt-4 space-y-4 animate-fade-in">
              {tab === "farm" && (
                <>
                  <SowStrip
                    boosters={boostersQ.data ?? []}
                    balance={data.farmingBalance}
                    rate={rate}
                    planting={startMut.isPending}
                    onPlant={(boosterId, amount) => startMut.mutate({ boosterId, amount })}
                  />

                  <div className="space-y-3">
                    <h2 className="text-sm font-semibold">
                      Your plots{" "}
                      <span className="font-normal text-muted-foreground">({data.plots.length} growing)</span>
                    </h2>

                    {data.plots.length === 0 && (
                      <div className="rounded-2xl border border-dashed border-border/60 p-8 text-center">
                        <div className="mx-auto mb-2 text-3xl">🌾</div>
                        <p className="text-sm font-medium">Your field is fallow</p>
                        <p className="mt-1 text-xs text-muted-foreground">
                          Sow your first seed above to start a cycle and begin earning XP.
                        </p>
                      </div>
                    )}

                    {data.plots.map((plot, i) => (
                      <PlotRow
                        key={plot.cycle.id}
                        plot={plot}
                        index={i}
                        rate={rate}
                        busy={busy}
                        splashing={splash?.cycleId === plot.cycle.id ? splash.action : null}
                        onCare={(action) => careMut.mutate({ cycleId: plot.cycle.id, action })}
                        onReap={() => reapMut.mutate(plot.cycle.id)}
                      />
                    ))}
                  </div>

                  <p className="flex items-start gap-2 rounded-xl border border-border/60 bg-muted/30 p-3 text-[11px] text-muted-foreground">
                    <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                    XP, levels, streaks, trophies and plot health are for fun only. Seed rewards come solely from the
                    cycle you chose when planting and never change based on how you play.
                  </p>
                </>
              )}

              {tab === "quests" && <QuestList quests={data.quests} />}
              {tab === "trophies" && <TrophyGrid achievements={data.achievements} />}
              {tab === "board" && <LeaderboardList rows={leadersQ.data ?? []} loading={leadersQ.isLoading} />}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
