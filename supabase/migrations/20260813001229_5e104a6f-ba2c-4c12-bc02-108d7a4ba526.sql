-- 1. Restrict app_settings reads to signed-in users only (was anon + authenticated).
DROP POLICY IF EXISTS "Anyone may read app settings" ON public.app_settings;
REVOKE SELECT ON public.app_settings FROM anon;
CREATE POLICY "Signed-in farmers may read app settings"
ON public.app_settings
FOR SELECT
TO authenticated
USING (true);

-- 2. Replay protection store for the signed internal test-credit endpoint.
CREATE TABLE public.test_credit_nonces (
  nonce text PRIMARY KEY,
  used_at timestamp with time zone NOT NULL DEFAULT now()
);

GRANT ALL ON public.test_credit_nonces TO service_role;

ALTER TABLE public.test_credit_nonces ENABLE ROW LEVEL SECURITY;

-- No policies for anon/authenticated: service_role only (bypasses RLS).
