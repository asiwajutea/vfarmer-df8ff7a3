# VFarmers — Interactive Farm Game

Turn `/farm` from "plant and wait" into a living, mobile-first farm. Every reward stays exactly as today: care actions earn XP, levels, streaks and badges only — never extra Seed, never less.

## The farm, redesigned

A vertical scrolling feed of plots, one per row, tuned for a thumb:

- **Farm header** — farmer level ring, XP bar to next level, day-streak flame, Farming balance, and today's weather chip.
- **Sow strip** — pick a seed duration (1 day / 3 days / 5 days / 7 days), enter Seed amount, plant. Same underlying cycle.
- **Plot rows** — each active cycle is a plot card showing an animated crop that visibly grows through 5 stages (seed → sprout → leafy → budding → ripe), the countdown, a health bar, and three care buttons: Water, Fertilize, Weed.
- **Reap** — matured plots switch to a glowing "Harvest" state with a small celebration on tap.
- **Empty state** — an illustrated fallow field inviting the first planting.

## Activities

- **Care actions** — Water (6h cooldown), Fertilize (24h), Weed (12h) per plot. Each tap gives XP, bumps plot health, advances a "care score", and plays a short animation. Cooldowns show as a countdown on the button.
- **Daily check-in** — one tap a day on the header. Streak counter with escalating XP (day 7 gives a bonus badge). Missing a day resets the streak.
- **Pests & weather** — each plot can randomly get an event (aphids, drought, storm, sunny spell). Harmful events show a badge and drop plot health until resolved with the matching action inside a time window; sunny spells give bonus XP for caring during them. Purely visual/XP — the cycle payout is untouched.
- **Quests & achievements** — rotating daily quests ("water 3 plots", "check in", "plant a 7-day seed") and permanent achievements ("first harvest", "30-day streak", "100 waterings") with badge art on a Trophies tab.

## Social

Solo farm plus a **Leaderboard** tab: top farmers by XP this week and all-time, showing display name, avatar, level and badge count. Own rank is pinned so it is always visible.

## Rewards are unchanged

XP, levels, streaks, badges and plot health are cosmetic. Seed rewards continue to come only from the existing cycle maturity math. The page states this plainly so no one reads the game as a yield multiplier.

## Technical notes

New tables (all RLS-scoped to `auth.uid()`, with GRANTs):

- `farm_profiles` — xp, level, streak_count, last_checkin_date, lifetime counters.
- `plot_care` — one row per care action (cycle_id, action, created_at) — drives cooldowns and quest counts.
- `plot_state` — per-cycle health, care_score, active event, event_expires_at.
- `quests` / `quest_progress` — daily quest definitions and per-user progress, reset on a rolling day boundary.
- `achievements` / `user_achievements` — static badge catalogue and unlocks.
- A `farm_leaderboard` view exposing only display_name, avatar_url, level, xp, badge count.

Security-definer RPCs `farm_care(cycle_id, action)`, `farm_checkin()`, and `farm_roll_events()` enforce cooldowns, award XP, advance quests and unlock achievements server-side — the client cannot mint XP. All of them call `assert_not_frozen(auth.uid())` like the rest of the money-adjacent routines. Reads and writes go through new server functions in `src/lib/farmgame.functions.ts` with `requireSupabaseAuth`.

Boosters get four canonical durations (24h, 72h, 120h, 168h) so the sow strip maps cleanly; existing admin booster management still controls reward rates and cost.

UI work: rewrite `src/routes/_authenticated/farm.tsx` as a tabbed shell (Farm / Quests / Trophies / Leaderboard) with new components under `src/components/farm/` — `FarmHeader`, `SowStrip`, `PlotRow`, `CropArt`, `CareButton`, `EventBadge`, `QuestList`, `TrophyGrid`, `LeaderboardList`. Crop stages and effects are CSS/SVG driven using existing design tokens, no new heavy dependency.
