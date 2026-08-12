-- 1. Lock down function execution -------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;

  -- Re-grant only the routines the app calls as a signed-in member.
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'admin_adjust_balance','admin_cancel_cycle','admin_create_booster','admin_create_coupon',
        'admin_create_coupons_bulk','admin_delete_booster','admin_force_mature_cycle',
        'admin_review_kyc','admin_review_request','admin_run_monthly_maintenance',
        'admin_set_booster_active','admin_set_coupon_active','admin_set_frozen',
        'admin_set_maintenance','admin_set_payout','admin_set_ticker','admin_update_booster',
        'escrow_accept','escrow_cancel','escrow_create','escrow_dispute','escrow_release','escrow_resolve',
        'find_profile_by_handle','fmt_seed','has_role','is_admin','is_username_available',
        'kyc_submit','lookup_referrer','mark_all_notifications_read','mark_notification_read',
        'p2p_send','pay_maintenance_fee','reap_cycle','redeem_coupon','start_cycle'
      )
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
  END LOOP;

  -- Signed-out visitors only need the referral-code preview on the sign-up screen.
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'lookup_referrer'
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon', r.sig);
  END LOOP;

  -- 2. Fixed search_path on every function.
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND (p.proconfig IS NULL OR NOT EXISTS (
        SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'))
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public', r.sig);
  END LOOP;
END $$;

-- 3. Coupons: no browsing of coupon records by ordinary members --------------
DROP POLICY IF EXISTS "Authenticated can view active coupons" ON public.coupons;
CREATE POLICY "Admins view coupons"
  ON public.coupons FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role));

-- 4. Affiliate commissions: earner + admin only ------------------------------
DROP POLICY IF EXISTS "Earners see own commissions" ON public.affiliate_commissions;
CREATE POLICY "Earners see own commissions"
  ON public.affiliate_commissions FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'::app_role));

-- 5. Storage: owner update/delete for kyc + proofs ---------------------------
DROP POLICY IF EXISTS "Owners update own kyc files" ON storage.objects;
CREATE POLICY "Owners update own kyc files"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'kyc' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'kyc' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "Owners delete own kyc files" ON storage.objects;
CREATE POLICY "Owners delete own kyc files"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'kyc' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "proofs owner update" ON storage.objects;
CREATE POLICY "proofs owner update"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'proofs' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'proofs' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "proofs owner delete" ON storage.objects;
CREATE POLICY "proofs owner delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'proofs' AND (storage.foldername(name))[1] = auth.uid()::text);

-- 6. user_roles: no self-service role changes --------------------------------
REVOKE INSERT, UPDATE, DELETE ON public.user_roles FROM authenticated;
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;

DROP POLICY IF EXISTS "Admins manage roles" ON public.user_roles;
CREATE POLICY "Admins manage roles"
  ON public.user_roles FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

DROP POLICY IF EXISTS "Only admins may write roles" ON public.user_roles;
CREATE POLICY "Only admins may write roles"
  ON public.user_roles AS RESTRICTIVE FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role) OR current_setting('request.method', true) IS NULL)
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));