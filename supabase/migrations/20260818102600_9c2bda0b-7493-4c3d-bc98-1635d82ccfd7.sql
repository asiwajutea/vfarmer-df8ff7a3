
DROP VIEW IF EXISTS public.farm_leaderboard;

CREATE OR REPLACE FUNCTION public.farm_leaderboard(p_limit integer DEFAULT 50)
RETURNS TABLE (
  user_id uuid,
  display_name text,
  avatar_url text,
  level integer,
  xp integer,
  streak_count integer,
  badges bigint,
  rank bigint
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM (
    SELECT fp.user_id,
           COALESCE(pr.display_name, pr.username, 'Farmer') AS display_name,
           pr.avatar_url,
           fp.level,
           fp.xp,
           fp.streak_count,
           (SELECT count(*) FROM public.user_achievements ua WHERE ua.user_id = fp.user_id) AS badges,
           ROW_NUMBER() OVER (ORDER BY fp.xp DESC, fp.user_id) AS rank
      FROM public.farm_profiles fp
      LEFT JOIN public.profiles pr ON pr.id = fp.user_id
     WHERE auth.uid() IS NOT NULL
  ) t
  ORDER BY t.rank
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 100));
$$;

REVOKE ALL ON FUNCTION public.farm_leaderboard(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.farm_leaderboard(integer) TO authenticated;
