
CREATE OR REPLACE FUNCTION public.is_frozen(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT frozen FROM public.profiles WHERE id = _user_id), false)
$$;

REVOKE ALL ON FUNCTION public.is_frozen(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_frozen(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.assert_not_frozen(_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.is_frozen(_user_id) THEN
    RAISE EXCEPTION 'Account frozen';
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.assert_not_frozen(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assert_not_frozen(uuid) TO authenticated, service_role;

-- ------------------------------------------------------------------ escrow
CREATE OR REPLACE FUNCTION public.escrow_accept(p_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_user uuid := auth.uid(); v_e public.escrow_trades%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  PERFORM public.assert_not_frozen(v_user);
  SELECT * INTO v_e FROM public.escrow_trades WHERE id = p_id FOR UPDATE;
  IF v_e.id IS NULL THEN RAISE EXCEPTION 'Escrow not found'; END IF;
  IF v_e.payee_id <> v_user THEN RAISE EXCEPTION 'Only the counterparty can accept'; END IF;
  IF v_e.status <> 'pending' THEN RAISE EXCEPTION 'Escrow is not pending'; END IF;
  UPDATE public.escrow_trades SET status = 'accepted', updated_at = now() WHERE id = p_id;
END $function$;

CREATE OR REPLACE FUNCTION public.escrow_cancel(p_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_user uuid := auth.uid(); v_e public.escrow_trades%ROWTYPE; v_pw public.wallets%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  PERFORM public.assert_not_frozen(v_user);
  SELECT * INTO v_e FROM public.escrow_trades WHERE id = p_id FOR UPDATE;
  IF v_e.id IS NULL THEN RAISE EXCEPTION 'Escrow not found'; END IF;
  IF v_user NOT IN (v_e.payer_id, v_e.payee_id) THEN RAISE EXCEPTION 'Not a participant'; END IF;
  IF v_e.status <> 'pending' THEN RAISE EXCEPTION 'Only a pending escrow can be cancelled'; END IF;
  SELECT * INTO v_pw FROM public.wallets WHERE user_id = v_e.payer_id AND kind = 'primary';
  IF v_pw.id IS NULL THEN RAISE EXCEPTION 'Payer primary wallet not found'; END IF;
  UPDATE public.escrow_trades SET status = 'cancelled', updated_at = now() WHERE id = p_id;
  PERFORM public.wallet_adjust(v_pw.id, v_e.amount, 'escrow_refund'::ledger_kind, 'Escrow cancelled - refund', 'escrow_trades', v_e.id);
END $function$;

CREATE OR REPLACE FUNCTION public.escrow_create(p_payee_id uuid, p_amount numeric, p_title text DEFAULT NULL::text, p_terms text DEFAULT NULL::text)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_payer uuid := auth.uid(); v_pw public.wallets%ROWTYPE; v_id uuid;
BEGIN
  IF v_payer IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  PERFORM public.assert_not_frozen(v_payer);
  IF p_payee_id IS NULL THEN RAISE EXCEPTION 'Counterparty required'; END IF;
  IF p_payee_id = v_payer THEN RAISE EXCEPTION 'Cannot open an escrow with yourself'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;
  IF public.is_frozen(p_payee_id) THEN RAISE EXCEPTION 'Counterparty account frozen'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.wallets WHERE user_id = p_payee_id AND kind = 'primary') THEN
    RAISE EXCEPTION 'Counterparty not found';
  END IF;
  SELECT * INTO v_pw FROM public.wallets WHERE user_id = v_payer AND kind = 'primary' FOR UPDATE;
  IF v_pw.id IS NULL THEN RAISE EXCEPTION 'Primary wallet not found'; END IF;
  IF (v_pw.balance - v_pw.locked) < p_amount THEN RAISE EXCEPTION 'Insufficient balance'; END IF;
  INSERT INTO public.escrow_trades (payer_id, payee_id, amount, title, terms, status)
  VALUES (v_payer, p_payee_id, p_amount, NULLIF(trim(p_title), ''), NULLIF(trim(p_terms), ''), 'pending')
  RETURNING id INTO v_id;
  PERFORM public.wallet_adjust(v_pw.id, -p_amount, 'escrow_lock'::ledger_kind,
    'Escrow funded' || COALESCE(': ' || NULLIF(trim(p_title), ''), ''), 'escrow_trades', v_id);
  RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.escrow_release(p_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_user uuid := auth.uid(); v_e public.escrow_trades%ROWTYPE; v_pw public.wallets%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  PERFORM public.assert_not_frozen(v_user);
  SELECT * INTO v_e FROM public.escrow_trades WHERE id = p_id FOR UPDATE;
  IF v_e.id IS NULL THEN RAISE EXCEPTION 'Escrow not found'; END IF;
  IF v_e.payer_id <> v_user THEN RAISE EXCEPTION 'Only the payer can release'; END IF;
  IF v_e.status NOT IN ('pending','accepted') THEN RAISE EXCEPTION 'Escrow cannot be released'; END IF;
  SELECT * INTO v_pw FROM public.wallets WHERE user_id = v_e.payee_id AND kind = 'primary';
  IF v_pw.id IS NULL THEN RAISE EXCEPTION 'Counterparty primary wallet not found'; END IF;
  UPDATE public.escrow_trades SET status = 'released', updated_at = now() WHERE id = p_id;
  PERFORM public.wallet_adjust(v_pw.id, v_e.amount, 'escrow_release'::ledger_kind, 'Escrow released', 'escrow_trades', v_e.id);
END $function$;

-- ------------------------------------------------------------------ p2p
CREATE OR REPLACE FUNCTION public.p2p_send(p_receiver_id uuid, p_amount numeric, p_note text DEFAULT NULL::text)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_sender   uuid := auth.uid();
  v_settings public.app_settings%ROWTYPE;
  v_fee_pct  numeric := 0;
  v_fee      numeric(20,8);
  v_total    numeric(20,8);
  v_sw       public.wallets%ROWTYPE;
  v_rw       public.wallets%ROWTYPE;
  v_id       uuid;
BEGIN
  IF v_sender IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  PERFORM public.assert_not_frozen(v_sender);
  IF p_receiver_id IS NULL THEN RAISE EXCEPTION 'Receiver required'; END IF;
  IF p_receiver_id = v_sender THEN RAISE EXCEPTION 'Cannot send to yourself'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;
  IF public.is_frozen(p_receiver_id) THEN RAISE EXCEPTION 'Recipient account frozen'; END IF;

  SELECT * INTO v_settings FROM public.app_settings WHERE id = true;
  IF v_settings.id IS NOT NULL THEN
    v_fee_pct := COALESCE(v_settings.p2p_fee_pct, 0);
  END IF;
  v_fee := round(p_amount * v_fee_pct / 100.0, 8);
  v_total := p_amount + v_fee;

  SELECT * INTO v_sw FROM public.wallets WHERE user_id = v_sender AND kind = 'primary';
  IF v_sw.id IS NULL THEN RAISE EXCEPTION 'Sender primary wallet not found'; END IF;
  SELECT * INTO v_rw FROM public.wallets WHERE user_id = p_receiver_id AND kind = 'primary';
  IF v_rw.id IS NULL THEN RAISE EXCEPTION 'Receiver primary wallet not found'; END IF;

  IF (v_sw.balance - v_sw.locked) < v_total THEN
    RAISE EXCEPTION 'Insufficient balance';
  END IF;

  INSERT INTO public.p2p_transfers (sender_id, receiver_id, amount, fee, note)
  VALUES (v_sender, p_receiver_id, p_amount, v_fee, p_note)
  RETURNING id INTO v_id;

  PERFORM public.wallet_transfer(
    v_sw.id, v_rw.id, p_amount,
    'p2p_out'::ledger_kind, 'p2p_in'::ledger_kind,
    COALESCE(p_note,'P2P transfer'), 'p2p_transfers', v_id
  );
  IF v_fee > 0 THEN
    PERFORM public.wallet_adjust(v_sw.id, -v_fee, 'p2p_fee'::ledger_kind, 'P2P fee', 'p2p_transfers', v_id);
  END IF;

  RETURN v_id;
END $function$;

-- ------------------------------------------------------------------ maintenance
CREATE OR REPLACE FUNCTION public.pay_maintenance_fee(p_fee_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_user    uuid := auth.uid();
  v_fee     public.maintenance_fees%ROWTYPE;
  v_wallet  public.wallets%ROWTYPE;
  v_settings public.app_settings%ROWTYPE;
  v_upline  record;
  v_pct     numeric(6,4);
  v_amount  numeric(20,8);
  v_uwallet public.wallets%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  PERFORM public.assert_not_frozen(v_user);
  SELECT * INTO v_fee FROM public.maintenance_fees WHERE id = p_fee_id FOR UPDATE;
  IF v_fee.id IS NULL THEN RAISE EXCEPTION 'Fee not found'; END IF;
  IF v_fee.user_id <> v_user THEN RAISE EXCEPTION 'Not your fee'; END IF;
  IF v_fee.status = 'paid' THEN RAISE EXCEPTION 'Already paid'; END IF;
  IF v_fee.status = 'waived' THEN RAISE EXCEPTION 'Fee waived'; END IF;

  SELECT * INTO v_wallet FROM public.wallets WHERE user_id = v_user AND kind = 'primary';
  IF v_wallet.id IS NULL THEN RAISE EXCEPTION 'Primary wallet not found'; END IF;

  PERFORM public.wallet_adjust(v_wallet.id, -v_fee.amount, 'maintenance_fee'::ledger_kind,
    'Maintenance fee ' || to_char(v_fee.period_start, 'YYYY-MM'), 'maintenance_fees', v_fee.id);

  UPDATE public.maintenance_fees SET status='paid', paid_at=now() WHERE id = p_fee_id;

  SELECT * INTO v_settings FROM public.app_settings WHERE id = true;
  FOR v_upline IN SELECT * FROM public.get_uplines(v_user) LOOP
    v_pct := CASE v_upline.generation
      WHEN 1 THEN v_settings.aff_maint_gen1_pct
      WHEN 2 THEN v_settings.aff_maint_gen2_pct
      WHEN 3 THEN v_settings.aff_maint_gen3_pct
    END;
    IF v_pct IS NULL OR v_pct <= 0 THEN CONTINUE; END IF;
    v_amount := round(v_fee.amount * v_pct, 8);
    IF v_amount <= 0 THEN CONTINUE; END IF;
    SELECT * INTO v_uwallet FROM public.wallets WHERE user_id = v_upline.user_id AND kind = 'primary';
    IF v_uwallet.id IS NULL THEN CONTINUE; END IF;

    INSERT INTO public.affiliate_commissions(user_id, from_user_id, generation, source, source_id, basis_amount, pct, amount)
      VALUES (v_upline.user_id, v_user, v_upline.generation, 'maintenance', v_fee.id, v_fee.amount, v_pct, v_amount);

    PERFORM public.wallet_adjust(v_uwallet.id, v_amount, 'affiliate_commission'::ledger_kind,
      'Gen ' || v_upline.generation || ' maintenance commission', 'maintenance_fees', v_fee.id);
  END LOOP;
END $function$;

-- ------------------------------------------------------------------ cycles
CREATE OR REPLACE FUNCTION public.reap_cycle(p_cycle_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_user    uuid := auth.uid();
  v_cycle   public.cycles%ROWTYPE;
  v_wallet  public.wallets%ROWTYPE;
  v_reward  numeric(20,8);
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  PERFORM public.assert_not_frozen(v_user);
  SELECT * INTO v_cycle FROM public.cycles WHERE id = p_cycle_id FOR UPDATE;
  IF v_cycle.id IS NULL THEN RAISE EXCEPTION 'Cycle not found'; END IF;
  IF v_cycle.user_id <> v_user THEN RAISE EXCEPTION 'Not your cycle'; END IF;
  IF v_cycle.status NOT IN ('active','matured') THEN RAISE EXCEPTION 'Cycle already %', v_cycle.status; END IF;
  IF v_cycle.matures_at > now() THEN RAISE EXCEPTION 'Cycle not yet matured'; END IF;

  SELECT * INTO v_wallet FROM public.wallets WHERE user_id = v_user AND kind = 'farming';
  IF v_wallet.id IS NULL THEN RAISE EXCEPTION 'Farming wallet not found'; END IF;

  v_reward := round(v_cycle.amount * v_cycle.reward_bps / 10000.0, 8);

  PERFORM public.wallet_adjust(v_wallet.id, v_cycle.amount, 'cycle_reap_principal', 'Reap principal', 'cycles', v_cycle.id);
  IF v_reward > 0 THEN
    PERFORM public.wallet_adjust(v_wallet.id, v_reward, 'cycle_reap_reward', 'Reap reward', 'cycles', v_cycle.id);
  END IF;

  UPDATE public.cycles SET status='reaped', reaped_at=now() WHERE id = p_cycle_id;

  PERFORM public.pay_cycle_commissions(p_cycle_id);
END $function$;

CREATE OR REPLACE FUNCTION public.start_cycle(p_booster_id uuid, p_amount numeric)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_user      uuid := auth.uid();
  v_booster   public.boosters%ROWTYPE;
  v_wallet    public.wallets%ROWTYPE;
  v_cycle_id  uuid;
  v_settings  public.app_settings%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  PERFORM public.assert_not_frozen(v_user);
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;

  SELECT * INTO v_booster FROM public.boosters WHERE id = p_booster_id AND active = true;
  IF v_booster.id IS NULL THEN RAISE EXCEPTION 'Booster not found or inactive'; END IF;

  SELECT * INTO v_settings FROM public.app_settings WHERE id = true;
  IF v_settings.id IS NOT NULL THEN
    IF p_amount < v_settings.min_cycle_seed THEN
      RAISE EXCEPTION 'Amount below minimum (% Seed)', v_settings.min_cycle_seed;
    END IF;
    IF p_amount > v_settings.max_cycle_seed THEN
      RAISE EXCEPTION 'Amount above maximum (% Seed)', v_settings.max_cycle_seed;
    END IF;
  END IF;

  SELECT * INTO v_wallet FROM public.wallets WHERE user_id = v_user AND kind = 'farming';
  IF v_wallet.id IS NULL THEN RAISE EXCEPTION 'Farming wallet not found'; END IF;

  PERFORM public.wallet_adjust(v_wallet.id, -p_amount, 'cycle_start', 'Start cycle: ' || v_booster.label, 'cycles', NULL);

  INSERT INTO public.cycles (user_id, booster_id, amount, duration_hours, reward_bps, matures_at)
  VALUES (v_user, v_booster.id, p_amount, v_booster.duration_hours, v_booster.reward_bps,
          now() + make_interval(hours => v_booster.duration_hours))
  RETURNING id INTO v_cycle_id;

  RETURN v_cycle_id;
END $function$;

-- ------------------------------------------------------------------ coupons
CREATE OR REPLACE FUNCTION public.redeem_coupon(p_code text)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_user   uuid := auth.uid();
  v_coupon public.coupons%ROWTYPE;
  v_wallet public.wallets%ROWTYPE;
  v_red_id uuid;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  PERFORM public.assert_not_frozen(v_user);
  IF p_code IS NULL OR length(trim(p_code)) = 0 THEN RAISE EXCEPTION 'Code required'; END IF;

  SELECT * INTO v_coupon FROM public.coupons WHERE code = upper(trim(p_code)) FOR UPDATE;
  IF v_coupon.id IS NULL THEN RAISE EXCEPTION 'Invalid coupon code'; END IF;
  IF NOT v_coupon.active THEN RAISE EXCEPTION 'Coupon is inactive'; END IF;
  IF v_coupon.expires_at IS NOT NULL AND v_coupon.expires_at < now() THEN
    RAISE EXCEPTION 'Coupon has expired';
  END IF;
  IF v_coupon.used_redemptions >= v_coupon.max_redemptions THEN
    RAISE EXCEPTION 'Coupon fully redeemed';
  END IF;
  IF EXISTS (SELECT 1 FROM public.coupon_redemptions WHERE coupon_id = v_coupon.id AND user_id = v_user) THEN
    RAISE EXCEPTION 'Already redeemed';
  END IF;

  SELECT * INTO v_wallet FROM public.wallets WHERE user_id = v_user AND kind = 'primary';
  IF v_wallet.id IS NULL THEN RAISE EXCEPTION 'Primary wallet not found'; END IF;

  INSERT INTO public.coupon_redemptions (coupon_id, user_id, amount)
  VALUES (v_coupon.id, v_user, v_coupon.amount)
  RETURNING id INTO v_red_id;

  UPDATE public.coupons SET used_redemptions = used_redemptions + 1 WHERE id = v_coupon.id;

  PERFORM public.wallet_adjust(
    v_wallet.id, v_coupon.amount,
    'coupon_redeem'::ledger_kind,
    'Coupon ' || v_coupon.code, 'coupons', v_coupon.id
  );

  RETURN v_red_id;
END $function$;

-- --------------------------------------------- admin approval of payouts
CREATE OR REPLACE FUNCTION public.admin_review_request(p_type text, p_id uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_admin uuid := auth.uid(); v_user uuid; v_amount numeric(20,8); v_status public.request_status; v_wallet uuid;
BEGIN
  IF v_admin IS NULL OR NOT public.is_admin(v_admin) THEN RAISE EXCEPTION 'Admin only'; END IF;
  IF p_type NOT IN ('deposit','withdrawal') THEN RAISE EXCEPTION 'Invalid request type'; END IF;
  IF p_type = 'deposit' THEN
    SELECT user_id, amount, status INTO v_user, v_amount, v_status FROM public.deposit_requests WHERE id = p_id FOR UPDATE;
  ELSE
    SELECT user_id, amount, status INTO v_user, v_amount, v_status FROM public.withdrawal_requests WHERE id = p_id FOR UPDATE;
  END IF;
  IF v_user IS NULL THEN RAISE EXCEPTION 'Request not found'; END IF;
  IF v_status <> 'pending' THEN RAISE EXCEPTION 'Request already %', v_status; END IF;
  IF p_approve AND public.is_frozen(v_user) THEN
    RAISE EXCEPTION 'Account frozen — unfreeze the account before approving';
  END IF;
  IF p_approve THEN
    SELECT id INTO v_wallet FROM public.wallets WHERE user_id = v_user AND kind = 'primary';
    IF v_wallet IS NULL THEN RAISE EXCEPTION 'Primary wallet not found'; END IF;
    IF p_type = 'deposit' THEN
      PERFORM public.wallet_adjust(v_wallet, v_amount, 'deposit'::ledger_kind, COALESCE(p_note,'Deposit approved'),'deposit_requests',p_id);
      UPDATE public.deposit_requests SET status='approved', admin_note=NULLIF(trim(p_note),''), updated_at=now() WHERE id=p_id;
    ELSE
      PERFORM public.wallet_adjust(v_wallet, -v_amount, 'withdrawal'::ledger_kind, COALESCE(p_note,'Withdrawal approved'),'withdrawal_requests',p_id);
      UPDATE public.withdrawal_requests SET status='approved', admin_note=NULLIF(trim(p_note),''), updated_at=now() WHERE id=p_id;
    END IF;
  ELSE
    IF p_type = 'deposit' THEN
      UPDATE public.deposit_requests SET status='rejected', admin_note=NULLIF(trim(p_note),''), updated_at=now() WHERE id=p_id;
    ELSE
      UPDATE public.withdrawal_requests SET status='rejected', admin_note=NULLIF(trim(p_note),''), updated_at=now() WHERE id=p_id;
    END IF;
  END IF;
  PERFORM public.admin_audit(v_admin, CASE WHEN p_approve THEN 'request_approved' ELSE 'request_rejected' END,
    p_type || '_request', p_id, jsonb_build_object('amount', v_amount, 'user_id', v_user, 'note', p_note));
END $function$;

-- ----------------------------------- block frozen users from new requests
DROP POLICY IF EXISTS "deposit_requests_not_frozen" ON public.deposit_requests;
CREATE POLICY "deposit_requests_not_frozen"
  ON public.deposit_requests AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (NOT public.is_frozen(auth.uid()));

DROP POLICY IF EXISTS "withdrawal_requests_not_frozen" ON public.withdrawal_requests;
CREATE POLICY "withdrawal_requests_not_frozen"
  ON public.withdrawal_requests AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (NOT public.is_frozen(auth.uid()));
