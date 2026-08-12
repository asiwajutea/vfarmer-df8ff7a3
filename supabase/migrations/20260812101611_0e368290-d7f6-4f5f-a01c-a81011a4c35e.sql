CREATE POLICY "Members view coupons they redeemed"
  ON public.coupons FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.coupon_redemptions r
    WHERE r.coupon_id = coupons.id AND r.user_id = auth.uid()
  ));