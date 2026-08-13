# Security review — VFarmers

Automated scanners (backend, connectors, dependencies) currently report **zero findings**, and every table in the database has row-level security enabled with policies. Wallets, ledger, profiles and KYC are all owner-scoped, and every money-moving database routine re-checks the caller's admin role server-side. Below is what my own read of the code turned up.

## Issues found

### 1. Public money-crediting endpoint (highest risk)
`/api/public/test-credit` is an unauthenticated, internet-reachable endpoint that credits any Farmer's Primary wallet. It is protected only by a shared secret signature. Two problems:

- **Replay is possible.** The timestamp field is optional, so a single captured valid request can be replayed forever to mint unlimited Seed. There is no nonce store.
- **It is a test tool living in production.** If the secret ever leaks (logs, a script, a shared machine), an attacker can create balances at will.

Recommended: remove the route from the production build, or restrict it to non-production only, require the timestamp, and persist used nonces so each signed request works once.

### 2. Platform settings readable by anonymous visitors
The `app_settings` table allows unrestricted read to logged-out visitors. That exposes fee percentages, affiliate commission rates, payout anchor/lock configuration and conversion rate to anyone.

Recommended: keep the small public subset (maintenance flags, marquee items, conversion rate) readable, and restrict the rest to signed-in users and admins.

### 3. Recipient lookup bypasses row-level security
The P2P recipient lookup falls back to a service-role query over all profiles when the normal lookup returns nothing. It bypasses database access rules and does a partial pattern match, so it can be used to probe for accounts.

Recommended: drop the fallback and rely on the exact-match database routine, which already returns only display fields.

### 4. Unauthenticated lookups have no throttling
The referrer lookup used on the signup page is callable by anyone and returns a name, username and avatar for any valid referral code. Codes are short, so they can be enumerated to harvest member names.

Recommended: keep it public (signup needs it) but add basic per-IP throttling and a generic response on repeated misses.

### 5. Dead code in the default-referral lookup
`getDefaultReferralCode` fetches up to 200 profile rows and then discards them, returning an environment value instead. It is unauthenticated and the query serves no purpose.

Recommended: delete the query and return the configured value directly.

## Not issues
- Only publishable/anon keys reach the browser; the service key stays server-side.
- All admin server functions are backed by admin checks inside the database routines, so a forged client call cannot escalate.
- No high or critical dependency vulnerabilities.

## Suggested order of work
1. Remove or harden the test-credit endpoint.
2. Tighten `app_settings` read access.
3. Remove the service-role recipient fallback and the dead profile query.
4. Add throttling to the public referrer lookup.
