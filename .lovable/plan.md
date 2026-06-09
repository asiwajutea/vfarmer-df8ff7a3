
## 1. Affiliate / maintenance fee audit

Quick verification pass — the previous migration is already applied (tables `affiliate_commissions`, `maintenance_fees` exist, RLS on, `app_settings` extended, RPCs `pay_cycle_commissions`, `pay_maintenance_fee`, `admin_run_monthly_maintenance`, `get_uplines`, `lookup_referrer` all present, `handle_new_user` resolves `referral_code`). Routes `/affiliate` and `/admin/affiliates` exist.

Small gaps to close in a follow-up migration:
- Add `INSERT/UPDATE/DELETE` admin policy on `affiliate_commissions` (currently only "Earners see own").
- Add a `unique (user_id, period_start)` constraint on `maintenance_fees` (the `admin_run_monthly_maintenance` RPC uses `ON CONFLICT (user_id, period_start)` but the constraint may be missing — verify and add if absent).
- Quick smoke: open `/affiliate`, `/admin/affiliates`, and admin `/admin/settings → Affiliate & maintenance settings` to confirm they render.

## 2. Maintenance mode

### Database (single migration)
Extend `app_settings` with maintenance-control columns:
- `maint_mode_global boolean default false` — kill switch for the whole site.
- `maint_message text` — banner shown to blocked users.
- `maint_pages jsonb default '{}'` — map of route key → boolean (true = blocked). Keys cover every user-facing page: `dashboard`, `farm`, `wallet`, `deposit`, `withdraw`, `send`, `coupons`, `escrow`, `notifications`, `profile`, `verify`, `affiliate`, plus landing keys `landing`, `auth_signin`.

`auth` (signup) is never blockable per requirement. Admin routes are never blocked.

### Server function
`src/lib/maintenance.functions.ts`:
- `getMaintenanceState()` — public, returns `{ global, message, pages }`.
- `adminSetMaintenance(state)` — admin only.

### Client gate
- `src/hooks/use-maintenance.ts` — fetches state via React Query (short stale time), exposes `isBlocked(pageKey)`.
- `src/components/MaintenanceGate.tsx` — if `global` OR `pages[key]` is true AND current user is not admin, render a maintenance screen with the admin's message; otherwise render `children`. Admin detection reuses `useIsAdmin()` (already exists).
- Wrap each protected route's component in `<MaintenanceGate pageKey="...">`. Wrap landing (`index.tsx`) too. Keep `/auth` and `/admin/*` unwrapped so signup and admin bypass always work.
- Optional small banner on the admin top bar when global mode is on, as a reminder.

### Admin UI
New page `/admin/maintenance` (link card on `/admin`):
- Global toggle + textarea for the message.
- Grid of per-page toggles auto-rendered from a `PAGES` list.
- "Save" button calls `adminSetMaintenance`.

## 3. Editable marquee (Ticker)

### Database (same migration as maintenance)
- `ticker_items jsonb default '[ ... seed defaults ... ]'` on `app_settings`. Each item `{ icon: string, label: string }` where `icon` ∈ a fixed allow-list (`users`, `sprout`, `trending-up`, `coins`, `flame`, `star`).
- `ticker_enabled boolean default true`.

### Component
- `src/components/Ticker.tsx` reads items via a lightweight public server fn `getTickerSettings()` (TanStack Query). Falls back to current hardcoded defaults while loading or on error so SSR/landing never blanks. Icon string → lucide component via a small map.

### Admin UI
On `/admin/settings`, add a "Landing ticker" section:
- Enable/disable toggle.
- Editable list of items (icon dropdown + label text), with add/remove/reorder buttons.
- Saves through `adminUpdatePlatformSettings` (extend the existing `PlatformSettings` type + server fn to include `ticker_enabled` and `ticker_items`).

## 4. Files

**Create**
- `supabase/migrations/<ts>_maintenance_and_ticker.sql` (also patches affiliate admin policy + maintenance_fees unique constraint).
- `src/lib/maintenance.functions.ts`
- `src/hooks/use-maintenance.ts`
- `src/components/MaintenanceGate.tsx`
- `src/routes/_authenticated/admin/maintenance.tsx`

**Edit**
- `src/components/Ticker.tsx` (load from settings)
- `src/routes/index.tsx` (wrap with `MaintenanceGate pageKey="landing"`)
- Every user route file under `src/routes/_authenticated/*.tsx` (wrap component, skip admin subtree)
- `src/routes/_authenticated/admin/index.tsx` (add Maintenance link)
- `src/routes/_authenticated/admin/settings.tsx` + `src/lib/settings.functions.ts` (ticker fields)
- `src/integrations/supabase/types.ts` regenerates after migration

## 5. Assumptions
- Maintenance mode applies to the rendered page UI; backend RPCs continue to function (admins can still operate, and so commissions/fees keep working in the background).
- Admin bypass is determined by the existing `has_role(uid,'admin')` check (already wired through `useIsAdmin`).
- `/auth` is always reachable so new users can register even during a full lockdown.
- Ticker icon set is curated (no arbitrary icon strings) to keep the bundle clean.

