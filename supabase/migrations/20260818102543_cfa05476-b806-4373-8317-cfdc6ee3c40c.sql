
-- =========================================================
-- Farm game layer (cosmetic XP / quests / achievements)
-- =========================================================

CREATE TABLE IF NOT EXISTS public.farm_profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  xp integer NOT NULL DEFAULT 0,
  level integer NOT NULL DEFAULT 1,
  streak_count integer NOT NULL DEFAULT 0,
  last_checkin_date date,
  lifetime_care integer NOT NULL DEFAULT 0,
  lifetime_harvests integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.farm_profiles TO authenticated;
GRANT ALL ON public.farm_profiles TO service_role;
ALTER TABLE public.farm_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "farm_profiles_select_own" ON public.farm_profiles
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.plot_care (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  cycle_id uuid NOT NULL REFERENCES public.cycles(id) ON DELETE CASCADE,
  action text NOT NULL CHECK (action IN ('water','fertilize','weed')),
  xp_awarded integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS plot_care_cycle_idx ON public.plot_care(cycle_id, action, created_at DESC);
CREATE INDEX IF NOT EXISTS plot_care_user_idx ON public.plot_care(user_id, created_at DESC);
GRANT SELECT ON public.plot_care TO authenticated;
GRANT ALL ON public.plot_care TO service_role;
ALTER TABLE public.plot_care ENABLE ROW LEVEL SECURITY;
CREATE POLICY "plot_care_select_own" ON public.plot_care
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.plot_state (
  cycle_id uuid PRIMARY KEY REFERENCES public.cycles(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  health integer NOT NULL DEFAULT 80,
  care_score integer NOT NULL DEFAULT 0,
  event_code text,
  event_started_at timestamptz,
  event_expires_at timestamptz,
  event_rolled_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.plot_state TO authenticated;
GRANT ALL ON public.plot_state TO service_role;
ALTER TABLE public.plot_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY "plot_state_select_own" ON public.plot_state
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.quests (
  code text PRIMARY KEY,
  label text NOT NULL,
  description text NOT NULL,
  metric text NOT NULL,
  target integer NOT NULL,
  xp integer NOT NULL,
  active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0
);
GRANT SELECT ON public.quests TO authenticated;
GRANT ALL ON public.quests TO service_role;
ALTER TABLE public.quests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "quests_select_all" ON public.quests
  FOR SELECT TO authenticated USING (active);

CREATE TABLE IF NOT EXISTS public.quest_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  quest_code text NOT NULL REFERENCES public.quests(code) ON DELETE CASCADE,
  day date NOT NULL DEFAULT (now() AT TIME ZONE 'utc')::date,
  progress integer NOT NULL DEFAULT 0,
  completed_at timestamptz,
  UNIQUE (user_id, quest_code, day)
);
GRANT SELECT ON public.quest_progress TO authenticated;
GRANT ALL ON public.quest_progress TO service_role;
ALTER TABLE public.quest_progress ENABLE ROW LEVEL SECURITY;
CREATE POLICY "quest_progress_select_own" ON public.quest_progress
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.achievements (
  code text PRIMARY KEY,
  label text NOT NULL,
  description text NOT NULL,
  icon text NOT NULL DEFAULT 'trophy',
  metric text NOT NULL,
  threshold integer NOT NULL,
  xp integer NOT NULL DEFAULT 0,
  sort_order integer NOT NULL DEFAULT 0
);
GRANT SELECT ON public.achievements TO authenticated;
GRANT ALL ON public.achievements TO service_role;
ALTER TABLE public.achievements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "achievements_select_all" ON public.achievements
  FOR SELECT TO authenticated USING (true);

CREATE TABLE IF NOT EXISTS public.user_achievements (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code text NOT NULL REFERENCES public.achievements(code) ON DELETE CASCADE,
  unlocked_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, code)
);
GRANT SELECT ON public.user_achievements TO authenticated;
GRANT ALL ON public.user_achievements TO service_role;
ALTER TABLE public.user_achievements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_achievements_select_own" ON public.user_achievements
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- ---------- catalogue seed ----------
INSERT INTO public.quests (code, label, description, metric, target, xp, sort_order) VALUES
  ('q_checkin',   'Morning rounds',  'Check in on your farm today',            'checkin',   1, 25, 1),
  ('q_water3',    'Water carrier',   'Water any plots 3 times',                'water',     3, 40, 2),
  ('q_fertilize', 'Feed the soil',   'Fertilize a plot',                       'fertilize', 1, 30, 3),
  ('q_weed',      'Clean rows',      'Clear weeds from a plot',                'weed',      1, 30, 4),
  ('q_plant',     'Sow the day',     'Plant a new seed today',                 'plant',     1, 50, 5),
  ('q_harvest',   'Bring it in',     'Harvest a matured plot today',           'harvest',   1, 50, 6)
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.achievements (code, label, description, icon, metric, threshold, xp, sort_order) VALUES
  ('a_first_seed',  'First Seed',       'Plant your very first crop',        'sprout',   'plants',     1,   50, 1),
  ('a_first_reap',  'First Harvest',    'Reap your first matured plot',      'wheat',    'harvests',   1,  100, 2),
  ('a_care10',      'Green Thumb',      'Perform 10 care actions',           'hand',     'care',      10,   50, 3),
  ('a_care100',     'Master Gardener',  'Perform 100 care actions',          'sparkles', 'care',     100,  250, 4),
  ('a_streak7',     'Week Strong',      'Keep a 7-day check-in streak',      'flame',    'streak',     7,  150, 5),
  ('a_streak30',    'Season Keeper',    'Keep a 30-day check-in streak',     'crown',    'streak',    30,  500, 6),
  ('a_harvest10',   'Bountiful',        'Reap 10 matured plots',             'trophy',   'harvests',  10,  200, 7),
  ('a_level5',      'Seasoned Farmer',  'Reach level 5',                     'star',     'level',      5,    0, 8),
  ('a_level10',     'Farm Legend',      'Reach level 10',                    'medal',    'level',     10,    0, 9)
ON CONFLICT (code) DO NOTHING;

-- ---------- helpers ----------
CREATE OR REPLACE FUNCTION public.farm_level_for_xp(p_xp integer)
RETURNS integer LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT GREATEST(1, FLOOR(SQRT(GREATEST(p_xp,0) / 100.0))::int + 1);
$$;

CREATE OR REPLACE FUNCTION public.farm_ensure_profile(_uid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.farm_profiles (user_id) VALUES (_uid)
  ON CONFLICT (user_id) DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION public.farm_award_xp(_uid uuid, _xp integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF _xp IS NULL OR _xp = 0 THEN RETURN; END IF;
  PERFORM public.farm_ensure_profile(_uid);
  UPDATE public.farm_profiles
     SET xp = GREATEST(0, xp + _xp),
         level = public.farm_level_for_xp(GREATEST(0, xp + _xp)),
         updated_at = now()
   WHERE user_id = _uid;
END $$;

CREATE OR REPLACE FUNCTION public.farm_bump_quest(_uid uuid, _metric text, _amount integer DEFAULT 1)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE q record; row_prog record;
BEGIN
  FOR q IN SELECT * FROM public.quests WHERE active AND metric = _metric LOOP
    INSERT INTO public.quest_progress (user_id, quest_code, day, progress)
    VALUES (_uid, q.code, (now() AT TIME ZONE 'utc')::date, 0)
    ON CONFLICT (user_id, quest_code, day) DO NOTHING;

    UPDATE public.quest_progress
       SET progress = LEAST(q.target, progress + _amount)
     WHERE user_id = _uid AND quest_code = q.code
       AND day = (now() AT TIME ZONE 'utc')::date
    RETURNING * INTO row_prog;

    IF row_prog.completed_at IS NULL AND row_prog.progress >= q.target THEN
      UPDATE public.quest_progress SET completed_at = now() WHERE id = row_prog.id;
      PERFORM public.farm_award_xp(_uid, q.xp);
    END IF;
  END LOOP;
END $$;

-- generic "care" quests also advance on any care action
CREATE OR REPLACE FUNCTION public.farm_check_achievements(_uid uuid)
RETURNS text[] LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  a record;
  v_care int; v_harvests int; v_plants int; v_streak int; v_level int; v_val int;
  unlocked text[] := '{}';
BEGIN
  PERFORM public.farm_ensure_profile(_uid);
  SELECT lifetime_care, streak_count, level INTO v_care, v_streak, v_level
    FROM public.farm_profiles WHERE user_id = _uid;
  SELECT count(*) INTO v_plants FROM public.cycles WHERE user_id = _uid;
  SELECT count(*) INTO v_harvests FROM public.cycles WHERE user_id = _uid AND status = 'reaped';

  FOR a IN SELECT * FROM public.achievements LOOP
    IF EXISTS (SELECT 1 FROM public.user_achievements WHERE user_id = _uid AND code = a.code) THEN
      CONTINUE;
    END IF;
    v_val := CASE a.metric
      WHEN 'care' THEN v_care
      WHEN 'harvests' THEN v_harvests
      WHEN 'plants' THEN v_plants
      WHEN 'streak' THEN v_streak
      WHEN 'level' THEN v_level
      ELSE 0 END;
    IF v_val >= a.threshold THEN
      INSERT INTO public.user_achievements (user_id, code) VALUES (_uid, a.code)
      ON CONFLICT DO NOTHING;
      PERFORM public.farm_award_xp(_uid, a.xp);
      unlocked := unlocked || a.code;
    END IF;
  END LOOP;
  RETURN unlocked;
END $$;

-- ---------- care action ----------
CREATE OR REPLACE FUNCTION public.farm_care(p_cycle_id uuid, p_action text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  c record; st record;
  cooldown interval;
  base_xp int;
  bonus_xp int := 0;
  last_at timestamptz;
  cured boolean := false;
  unlocked text[];
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  PERFORM public.assert_not_frozen(uid);

  IF p_action NOT IN ('water','fertilize','weed') THEN
    RAISE EXCEPTION 'Unknown action';
  END IF;

  SELECT * INTO c FROM public.cycles WHERE id = p_cycle_id AND user_id = uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Plot not found'; END IF;
  IF c.status NOT IN ('active','matured') THEN RAISE EXCEPTION 'This plot is no longer growing'; END IF;

  cooldown := CASE p_action WHEN 'water' THEN interval '6 hours'
                            WHEN 'weed' THEN interval '12 hours'
                            ELSE interval '24 hours' END;
  base_xp := CASE p_action WHEN 'water' THEN 10 WHEN 'weed' THEN 15 ELSE 20 END;

  SELECT max(created_at) INTO last_at FROM public.plot_care
   WHERE cycle_id = p_cycle_id AND action = p_action;
  IF last_at IS NOT NULL AND last_at + cooldown > now() THEN
    RAISE EXCEPTION 'Not ready yet — try again later';
  END IF;

  INSERT INTO public.plot_state (cycle_id, user_id) VALUES (p_cycle_id, uid)
  ON CONFLICT (cycle_id) DO NOTHING;
  SELECT * INTO st FROM public.plot_state WHERE cycle_id = p_cycle_id;

  -- resolving an active event with the right action
  IF st.event_code IS NOT NULL AND (st.event_expires_at IS NULL OR st.event_expires_at > now()) THEN
    IF (st.event_code = 'drought' AND p_action = 'water')
      OR (st.event_code = 'aphids' AND p_action = 'weed')
      OR (st.event_code = 'storm' AND p_action = 'fertilize')
      OR (st.event_code = 'frost' AND p_action = 'fertilize') THEN
      cured := true;
      bonus_xp := 25;
    ELSIF st.event_code = 'sunny' THEN
      bonus_xp := 5;
    END IF;
  END IF;

  INSERT INTO public.plot_care (user_id, cycle_id, action, xp_awarded)
  VALUES (uid, p_cycle_id, p_action, base_xp + bonus_xp);

  UPDATE public.plot_state
     SET health = LEAST(100, health + CASE WHEN cured THEN 20 ELSE 8 END),
         care_score = care_score + 1,
         event_code = CASE WHEN cured THEN NULL ELSE event_code END,
         event_expires_at = CASE WHEN cured THEN NULL ELSE event_expires_at END,
         event_started_at = CASE WHEN cured THEN NULL ELSE event_started_at END,
         updated_at = now()
   WHERE cycle_id = p_cycle_id;

  PERFORM public.farm_ensure_profile(uid);
  UPDATE public.farm_profiles SET lifetime_care = lifetime_care + 1, updated_at = now() WHERE user_id = uid;
  PERFORM public.farm_award_xp(uid, base_xp + bonus_xp);
  PERFORM public.farm_bump_quest(uid, p_action, 1);
  PERFORM public.farm_bump_quest(uid, 'care', 1);
  unlocked := public.farm_check_achievements(uid);

  RETURN jsonb_build_object('xp', base_xp + bonus_xp, 'cured', cured, 'unlocked', to_jsonb(unlocked));
END $$;

-- ---------- daily check-in ----------
CREATE OR REPLACE FUNCTION public.farm_checkin()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  p record;
  today date := (now() AT TIME ZONE 'utc')::date;
  new_streak int;
  gain int;
  unlocked text[];
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  PERFORM public.assert_not_frozen(uid);
  PERFORM public.farm_ensure_profile(uid);
  SELECT * INTO p FROM public.farm_profiles WHERE user_id = uid;

  IF p.last_checkin_date = today THEN
    RAISE EXCEPTION 'Already checked in today';
  END IF;

  new_streak := CASE WHEN p.last_checkin_date = today - 1 THEN p.streak_count + 1 ELSE 1 END;
  gain := 25 + LEAST(new_streak, 7) * 5;

  UPDATE public.farm_profiles
     SET streak_count = new_streak, last_checkin_date = today, updated_at = now()
   WHERE user_id = uid;

  PERFORM public.farm_award_xp(uid, gain);
  PERFORM public.farm_bump_quest(uid, 'checkin', 1);
  unlocked := public.farm_check_achievements(uid);

  RETURN jsonb_build_object('streak', new_streak, 'xp', gain, 'unlocked', to_jsonb(unlocked));
END $$;

-- ---------- sync: events, harvest/plant quests, achievements ----------
CREATE OR REPLACE FUNCTION public.farm_sync()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  c record;
  today date := (now() AT TIME ZONE 'utc')::date;
  reaped_total int; planted_today int; reaped_today int;
  p record; new_harvests int; roll numeric; ev text;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  PERFORM public.farm_ensure_profile(uid);

  -- ensure a plot_state row for every live plot; expire stale events
  FOR c IN SELECT id FROM public.cycles WHERE user_id = uid AND status IN ('active','matured') LOOP
    INSERT INTO public.plot_state (cycle_id, user_id) VALUES (c.id, uid)
    ON CONFLICT (cycle_id) DO NOTHING;
  END LOOP;

  UPDATE public.plot_state
     SET health = GREATEST(0, health - CASE WHEN event_code = 'sunny' THEN 0 ELSE 10 END),
         event_code = NULL, event_started_at = NULL, event_expires_at = NULL, updated_at = now()
   WHERE user_id = uid AND event_code IS NOT NULL AND event_expires_at < now();

  -- roll new events at most every 6 hours per plot
  FOR c IN
    SELECT ps.cycle_id FROM public.plot_state ps
    JOIN public.cycles cy ON cy.id = ps.cycle_id
    WHERE ps.user_id = uid AND cy.status = 'active'
      AND ps.event_code IS NULL
      AND (ps.event_rolled_at IS NULL OR ps.event_rolled_at < now() - interval '6 hours')
  LOOP
    roll := random();
    ev := NULL;
    IF roll < 0.14 THEN ev := 'drought';
    ELSIF roll < 0.26 THEN ev := 'aphids';
    ELSIF roll < 0.34 THEN ev := 'storm';
    ELSIF roll < 0.40 THEN ev := 'frost';
    ELSIF roll < 0.55 THEN ev := 'sunny';
    END IF;

    UPDATE public.plot_state
       SET event_rolled_at = now(),
           event_code = ev,
           event_started_at = CASE WHEN ev IS NULL THEN NULL ELSE now() END,
           event_expires_at = CASE WHEN ev IS NULL THEN NULL ELSE now() + interval '12 hours' END,
           updated_at = now()
     WHERE cycle_id = c.cycle_id;
  END LOOP;

  -- harvest XP for newly reaped plots
  SELECT count(*) INTO reaped_total FROM public.cycles WHERE user_id = uid AND status = 'reaped';
  SELECT * INTO p FROM public.farm_profiles WHERE user_id = uid;
  new_harvests := GREATEST(0, reaped_total - p.lifetime_harvests);
  IF new_harvests > 0 THEN
    UPDATE public.farm_profiles SET lifetime_harvests = reaped_total, updated_at = now() WHERE user_id = uid;
    PERFORM public.farm_award_xp(uid, new_harvests * 50);
  END IF;

  -- daily plant/harvest quest progress derived from cycles
  SELECT count(*) INTO planted_today FROM public.cycles
   WHERE user_id = uid AND (created_at AT TIME ZONE 'utc')::date = today;
  SELECT count(*) INTO reaped_today FROM public.cycles
   WHERE user_id = uid AND reaped_at IS NOT NULL AND (reaped_at AT TIME ZONE 'utc')::date = today;

  IF planted_today > 0 THEN PERFORM public.farm_bump_quest(uid, 'plant', planted_today); END IF;
  IF reaped_today > 0 THEN PERFORM public.farm_bump_quest(uid, 'harvest', reaped_today); END IF;

  PERFORM public.farm_check_achievements(uid);
  RETURN jsonb_build_object('ok', true, 'newHarvests', new_harvests);
END $$;

-- ---------- leaderboard ----------
CREATE OR REPLACE VIEW public.farm_leaderboard
WITH (security_invoker = off) AS
  SELECT fp.user_id,
         COALESCE(pr.display_name, pr.username, 'Farmer') AS display_name,
         pr.avatar_url,
         fp.level,
         fp.xp,
         fp.streak_count,
         (SELECT count(*) FROM public.user_achievements ua WHERE ua.user_id = fp.user_id) AS badges,
         ROW_NUMBER() OVER (ORDER BY fp.xp DESC, fp.user_id) AS rank
    FROM public.farm_profiles fp
    LEFT JOIN public.profiles pr ON pr.id = fp.user_id;

GRANT SELECT ON public.farm_leaderboard TO authenticated;

-- ---------- execute grants ----------
REVOKE ALL ON FUNCTION public.farm_care(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.farm_checkin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.farm_sync() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.farm_award_xp(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.farm_bump_quest(uuid, text, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.farm_check_achievements(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.farm_ensure_profile(uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.farm_care(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.farm_checkin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.farm_sync() TO authenticated;
