import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import type { Database } from "@/integrations/supabase/types";

export type FarmProfile = Database["public"]["Tables"]["farm_profiles"]["Row"];
export type PlotState = Database["public"]["Tables"]["plot_state"]["Row"];
export type Quest = Database["public"]["Tables"]["quests"]["Row"];
export type Achievement = Database["public"]["Tables"]["achievements"]["Row"];
export type CycleRow = Database["public"]["Tables"]["cycles"]["Row"];

export type Plot = {
  cycle: CycleRow;
  state: PlotState | null;
  /** ISO timestamp of the last time each care action ran on this plot. */
  lastCare: Record<string, string | null>;
};

export type QuestView = Quest & { progress: number; completed: boolean };
export type AchievementView = Achievement & { unlockedAt: string | null };

export type FarmOverview = {
  profile: {
    xp: number;
    level: number;
    streak: number;
    checkedInToday: boolean;
    lifetimeCare: number;
    lifetimeHarvests: number;
  };
  plots: Plot[];
  history: CycleRow[];
  quests: QuestView[];
  achievements: AchievementView[];
  farmingBalance: number;
};

/** Runs the server-side sync (events, harvest XP, quest rollup) then reads everything. */
export const getFarmOverview = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<FarmOverview> => {
    const sb = context.supabase;
    const uid = context.userId;

    await sb.rpc("farm_sync");

    const today = new Date().toISOString().slice(0, 10);

    const [profileRes, cyclesRes, stateRes, careRes, questsRes, progressRes, achRes, userAchRes, walletRes] =
      await Promise.all([
        sb.from("farm_profiles").select("*").eq("user_id", uid).maybeSingle(),
        sb.from("cycles").select("*").eq("user_id", uid).order("created_at", { ascending: false }).limit(100),
        sb.from("plot_state").select("*").eq("user_id", uid),
        sb.from("plot_care").select("cycle_id, action, created_at").eq("user_id", uid).order("created_at", { ascending: false }).limit(500),
        sb.from("quests").select("*").eq("active", true).order("sort_order"),
        sb.from("quest_progress").select("*").eq("user_id", uid).eq("day", today),
        sb.from("achievements").select("*").order("sort_order"),
        sb.from("user_achievements").select("*").eq("user_id", uid),
        sb.from("wallets").select("balance").eq("user_id", uid).eq("kind", "farming").maybeSingle(),
      ]);

    const cycles = cyclesRes.data ?? [];
    const states = new Map((stateRes.data ?? []).map((s) => [s.cycle_id, s]));

    const lastCareMap = new Map<string, Record<string, string | null>>();
    for (const row of careRes.data ?? []) {
      const entry = lastCareMap.get(row.cycle_id) ?? {};
      if (!entry[row.action]) entry[row.action] = row.created_at;
      lastCareMap.set(row.cycle_id, entry);
    }

    const live = cycles.filter((c) => c.status === "active" || c.status === "matured");
    const plots: Plot[] = live.map((cycle) => ({
      cycle,
      state: states.get(cycle.id) ?? null,
      lastCare: lastCareMap.get(cycle.id) ?? {},
    }));

    const progressByCode = new Map((progressRes.data ?? []).map((p) => [p.quest_code, p]));
    const quests: QuestView[] = (questsRes.data ?? []).map((q) => {
      const p = progressByCode.get(q.code);
      return { ...q, progress: p?.progress ?? 0, completed: Boolean(p?.completed_at) };
    });

    const unlocked = new Map((userAchRes.data ?? []).map((u) => [u.code, u.unlocked_at]));
    const achievements: AchievementView[] = (achRes.data ?? []).map((a) => ({
      ...a,
      unlockedAt: unlocked.get(a.code) ?? null,
    }));

    const p = profileRes.data;
    return {
      profile: {
        xp: p?.xp ?? 0,
        level: p?.level ?? 1,
        streak: p?.streak_count ?? 0,
        checkedInToday: p?.last_checkin_date === today,
        lifetimeCare: p?.lifetime_care ?? 0,
        lifetimeHarvests: p?.lifetime_harvests ?? 0,
      },
      plots,
      history: cycles.filter((c) => c.status === "reaped" || c.status === "cancelled").slice(0, 20),
      quests,
      achievements,
      farmingBalance: Number(walletRes.data?.balance ?? 0),
    };
  });

const careInput = z.object({
  cycleId: z.string().uuid(),
  action: z.enum(["water", "fertilize", "weed"]),
});

export const careForPlot = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: unknown) => careInput.parse(d))
  .handler(async ({ data, context }): Promise<{ xp: number; cured: boolean; unlocked: string[] }> => {
    const { data: res, error } = await context.supabase.rpc("farm_care", {
      p_cycle_id: data.cycleId,
      p_action: data.action,
    });
    if (error) throw new Error(error.message);
    const r = (res ?? {}) as { xp?: number; cured?: boolean; unlocked?: string[] };
    return { xp: Number(r.xp ?? 0), cured: Boolean(r.cured), unlocked: r.unlocked ?? [] };
  });

export const dailyCheckin = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<{ streak: number; xp: number; unlocked: string[] }> => {
    const { data: res, error } = await context.supabase.rpc("farm_checkin");
    if (error) throw new Error(error.message);
    const r = (res ?? {}) as { streak?: number; xp?: number; unlocked?: string[] };
    return { streak: Number(r.streak ?? 0), xp: Number(r.xp ?? 0), unlocked: r.unlocked ?? [] };
  });

export type LeaderRow = {
  user_id: string;
  display_name: string;
  avatar_url: string | null;
  level: number;
  xp: number;
  streak_count: number;
  badges: number;
  rank: number;
  isMe: boolean;
};

export const getLeaderboard = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<LeaderRow[]> => {
    const { data, error } = await context.supabase.rpc("farm_leaderboard", { p_limit: 50 });
    if (error) throw new Error(error.message);
    return (data ?? []).map((r) => ({
      user_id: r.user_id,
      display_name: r.display_name ?? "Farmer",
      avatar_url: r.avatar_url,
      level: r.level,
      xp: r.xp,
      streak_count: r.streak_count,
      badges: Number(r.badges),
      rank: Number(r.rank),
      isMe: r.user_id === context.userId,
    }));
  });
