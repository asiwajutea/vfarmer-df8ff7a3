
DO $$ BEGIN
  CREATE TYPE public.notification_kind AS ENUM (
    'cycle_matured','cycle_reaped','deposit_approved','deposit_rejected','withdrawal_approved','withdrawal_rejected',
    'transfer_received','escrow_created','escrow_accepted','escrow_released','escrow_cancelled','escrow_disputed','escrow_refunded',
    'affiliate_commission','maintenance_due','admin_balance_adjusted','system');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind public.notification_kind NOT NULL,
  title text NOT NULL, body text, ref_table text, ref_id uuid,
  read_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS notifications_user_created_idx ON public.notifications (user_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS notifications_user_unread_idx ON public.notifications (user_id) WHERE read_at IS NULL;
GRANT SELECT, UPDATE ON public.notifications TO authenticated;
GRANT ALL ON public.notifications TO service_role;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users read own notifications" ON public.notifications;
CREATE POLICY "Users read own notifications" ON public.notifications FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users update own notifications" ON public.notifications;
CREATE POLICY "Users update own notifications" ON public.notifications FOR UPDATE TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.notify_user(p_user uuid, p_kind public.notification_kind, p_title text, p_body text DEFAULT NULL, p_ref_table text DEFAULT NULL, p_ref_id uuid DEFAULT NULL)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  INSERT INTO public.notifications (user_id, kind, title, body, ref_table, ref_id) VALUES (p_user, p_kind, p_title, p_body, p_ref_table, p_ref_id);
$$;

CREATE OR REPLACE FUNCTION public.fmt_seed(p_amount numeric) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT trim(trailing '.' FROM trim(trailing '0' FROM to_char(p_amount, 'FM999999999990.00######'))) || ' Seed';
$$;

CREATE OR REPLACE FUNCTION public.tg_notify_cycle() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_reward numeric(20,8);
BEGIN
  IF TG_OP='UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status='reaped' THEN
      v_reward := round(NEW.amount * NEW.reward_bps / 10000.0, 8);
      PERFORM public.notify_user(NEW.user_id,'cycle_reaped','Cycle reaped',
        'You harvested ' || public.fmt_seed(NEW.amount + v_reward) || ' (principal + ' || public.fmt_seed(v_reward) || ' reward).','cycles',NEW.id);
    ELSIF NEW.status='matured' THEN
      PERFORM public.notify_user(NEW.user_id,'cycle_matured','Cycle matured','Your cycle is ready to reap.','cycles',NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS notify_cycle ON public.cycles;
CREATE TRIGGER notify_cycle AFTER UPDATE ON public.cycles FOR EACH ROW EXECUTE FUNCTION public.tg_notify_cycle();

CREATE OR REPLACE FUNCTION public.tg_notify_deposit_request() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF TG_OP='UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status='approved' THEN
      PERFORM public.notify_user(NEW.user_id,'deposit_approved','Deposit approved',
        public.fmt_seed(NEW.amount) || ' was credited to your wallet.' || COALESCE(' Note: ' || NULLIF(trim(NEW.admin_note),''),''),'deposit_requests',NEW.id);
    ELSIF NEW.status='rejected' THEN
      PERFORM public.notify_user(NEW.user_id,'deposit_rejected','Deposit rejected',
        'Your deposit of ' || public.fmt_seed(NEW.amount) || ' was not approved.' || COALESCE(' Note: ' || NULLIF(trim(NEW.admin_note),''),''),'deposit_requests',NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS notify_deposit_request ON public.deposit_requests;
CREATE TRIGGER notify_deposit_request AFTER UPDATE ON public.deposit_requests FOR EACH ROW EXECUTE FUNCTION public.tg_notify_deposit_request();

CREATE OR REPLACE FUNCTION public.tg_notify_withdrawal_request() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF TG_OP='UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status='approved' THEN
      PERFORM public.notify_user(NEW.user_id,'withdrawal_approved','Withdrawal approved',
        public.fmt_seed(NEW.amount) || ' withdrawal was approved.' || COALESCE(' Note: ' || NULLIF(trim(NEW.admin_note),''),''),'withdrawal_requests',NEW.id);
    ELSIF NEW.status='rejected' THEN
      PERFORM public.notify_user(NEW.user_id,'withdrawal_rejected','Withdrawal rejected',
        'Your withdrawal of ' || public.fmt_seed(NEW.amount) || ' was not approved.' || COALESCE(' Note: ' || NULLIF(trim(NEW.admin_note),''),''),'withdrawal_requests',NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS notify_withdrawal_request ON public.withdrawal_requests;
CREATE TRIGGER notify_withdrawal_request AFTER UPDATE ON public.withdrawal_requests FOR EACH ROW EXECUTE FUNCTION public.tg_notify_withdrawal_request();

CREATE OR REPLACE FUNCTION public.tg_notify_p2p() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_from text;
BEGIN
  IF NEW.status IS DISTINCT FROM 'completed' THEN RETURN NEW; END IF;
  SELECT COALESCE(NULLIF(display_name,''),'@' || username,'a Farmer') INTO v_from FROM public.profiles WHERE id = NEW.sender_id;
  PERFORM public.notify_user(NEW.receiver_id,'transfer_received','Payment received',
    'You received ' || public.fmt_seed(NEW.amount) || ' from ' || COALESCE(v_from,'a Farmer') || '.' ||
    COALESCE(' "' || NULLIF(trim(NEW.note),'') || '"',''),'p2p_transfers',NEW.id);
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS notify_p2p ON public.p2p_transfers;
CREATE TRIGGER notify_p2p AFTER INSERT ON public.p2p_transfers FOR EACH ROW EXECUTE FUNCTION public.tg_notify_p2p();

CREATE OR REPLACE FUNCTION public.tg_notify_escrow() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_label text;
BEGIN
  v_label := COALESCE(' (' || NULLIF(trim(NEW.title),'') || ')','');
  IF TG_OP='INSERT' THEN
    PERFORM public.notify_user(NEW.payee_id,'escrow_created','New escrow offer',
      'An escrow of ' || public.fmt_seed(NEW.amount) || ' was funded for you' || v_label || '.','escrow_trades',NEW.id);
    RETURN NEW;
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    CASE NEW.status
      WHEN 'accepted' THEN PERFORM public.notify_user(NEW.payer_id,'escrow_accepted','Escrow accepted','Your counterparty accepted the escrow' || v_label || '.','escrow_trades',NEW.id);
      WHEN 'released' THEN PERFORM public.notify_user(NEW.payee_id,'escrow_released','Escrow released', public.fmt_seed(NEW.amount) || ' was released to you' || v_label || '.','escrow_trades',NEW.id);
      WHEN 'cancelled' THEN
        PERFORM public.notify_user(NEW.payer_id,'escrow_cancelled','Escrow cancelled','The escrow' || v_label || ' was cancelled and refunded.','escrow_trades',NEW.id);
        PERFORM public.notify_user(NEW.payee_id,'escrow_cancelled','Escrow cancelled','The escrow' || v_label || ' was cancelled.','escrow_trades',NEW.id);
      WHEN 'disputed' THEN
        PERFORM public.notify_user(NEW.payer_id,'escrow_disputed','Escrow disputed','The escrow' || v_label || ' is under dispute.','escrow_trades',NEW.id);
        PERFORM public.notify_user(NEW.payee_id,'escrow_disputed','Escrow disputed','The escrow' || v_label || ' is under dispute.','escrow_trades',NEW.id);
      WHEN 'refunded' THEN PERFORM public.notify_user(NEW.payer_id,'escrow_refunded','Escrow refunded', public.fmt_seed(NEW.amount) || ' was refunded to you' || v_label || '.','escrow_trades',NEW.id);
      ELSE NULL;
    END CASE;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS notify_escrow ON public.escrow_trades;
CREATE TRIGGER notify_escrow AFTER INSERT OR UPDATE ON public.escrow_trades FOR EACH ROW EXECUTE FUNCTION public.tg_notify_escrow();

CREATE OR REPLACE FUNCTION public.tg_notify_affiliate_commission() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.notify_user(NEW.user_id,'affiliate_commission','Commission earned',
    'You earned ' || public.fmt_seed(NEW.amount) || ' (Gen ' || NEW.generation || ' ' || NEW.source || ' commission).','affiliate_commissions',NEW.id);
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS notify_affiliate_commission ON public.affiliate_commissions;
CREATE TRIGGER notify_affiliate_commission AFTER INSERT ON public.affiliate_commissions FOR EACH ROW EXECUTE FUNCTION public.tg_notify_affiliate_commission();

CREATE OR REPLACE FUNCTION public.tg_notify_maintenance_fee() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.status='due' THEN
    PERFORM public.notify_user(NEW.user_id,'maintenance_due','Maintenance fee due',
      'A maintenance fee of ' || public.fmt_seed(NEW.amount) || ' for ' || to_char(NEW.period_start,'Mon YYYY') || ' is now due.','maintenance_fees',NEW.id);
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS notify_maintenance_fee ON public.maintenance_fees;
CREATE TRIGGER notify_maintenance_fee AFTER INSERT ON public.maintenance_fees FOR EACH ROW EXECUTE FUNCTION public.tg_notify_maintenance_fee();

CREATE OR REPLACE FUNCTION public.tg_notify_admin_adjust() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.kind IN ('admin_credit','admin_debit') THEN
    PERFORM public.notify_user(NEW.user_id,'admin_balance_adjusted',
      CASE WHEN NEW.amount >= 0 THEN 'Wallet credited' ELSE 'Wallet debited' END,
      'An administrator ' || CASE WHEN NEW.amount >= 0 THEN 'credited ' ELSE 'debited ' END || public.fmt_seed(abs(NEW.amount)) || '.' ||
      COALESCE(' ' || NULLIF(trim(NEW.memo),''),''),'ledger_entries',NEW.id);
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS notify_admin_adjust ON public.ledger_entries;
CREATE TRIGGER notify_admin_adjust AFTER INSERT ON public.ledger_entries FOR EACH ROW EXECUTE FUNCTION public.tg_notify_admin_adjust();

CREATE OR REPLACE FUNCTION public.mark_notification_read(p_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  UPDATE public.notifications SET read_at=COALESCE(read_at,now()) WHERE id=p_id AND user_id=v_user;
END $$;

CREATE OR REPLACE FUNCTION public.mark_all_notifications_read() RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user uuid := auth.uid(); v_count integer;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  UPDATE public.notifications SET read_at=now() WHERE user_id=v_user AND read_at IS NULL;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  RETURN v_count;
END $$;

GRANT EXECUTE ON FUNCTION public.mark_notification_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_all_notifications_read() TO authenticated;

ALTER TABLE public.notifications REPLICA IDENTITY FULL;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL;
END $$;
