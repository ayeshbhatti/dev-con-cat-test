# Solution notes

## Scope and run instructions

A compact Rails/PostgreSQL application using the supplied mock vendor data. [README.md](README.md) contains setup commands, seed instructions, demo users, scenarios, and test commands. Start the server with `bundle exec rails server`; the dashboard is at `http://localhost:3000/` and the backend demo is at `http://localhost:3000/demo.html`.

The scope prioritizes account isolation, a defensible consensus policy, atomic credit accounting, preserved verification evidence, and a working browser-to-backend flow. Real vendor APIs, payments, reviewer workflows, and production deployment are outside this implementation.

## Model

| Model | Responsibility |
| --- | --- |
| Account | Tenant, plan/status, modules/prices, balance and imported burn estimate |
| User | BCrypt password and role; account-bound except super_admin |
| Pixel | Tenant-owned public ID, hostname allowlist, enabled modules, active flag |
| CaptureSession | Visit context and bounded field interactions |
| Lead | Pixel-derived tenant/contact, capture session, activity-token digest |
| VerificationRun | Module/cost snapshot, state, verdict, points and reasons |
| LayerResult | One explicit layer state/result per run |
| ActivityEvent | Persisted verification feed |
| ConsentCertificate | Immutable-at-model-level evidence snapshot and digest |
| CreditLedgerEntry | Atomic run debit with unique idempotency key |
| ProviderDataset | Imported mock datasets |

A capture session has a unique lead index. Each run/layer pair and debit idempotency key is unique. Runs own provider results and certificates; historical verification is not overwritten on the lead.

Certificate/ledger has_one run associations do not yet have database-level unique run indexes. Normal job/intake paths prevent duplicate creation; database constraints would strengthen this.

## Consensus

Only returned results are scored. Handle unavailable results first; they force at least REVIEW unless another confirmed condition requires REJECT.

Hard stops: confirmed litigator, DNC/internal DNC, returned invalid/mismatched consent, Anura bad, Tor, exact duplicate, synthetic/reused voice. These are explicit product-policy choices: confirmed restrictions, invalid evidence, clear fraud, and exact duplication should not be cancelled out by unrelated positive checks. Disagreement and uncertain signals receive points instead.

Weighted signals: VPN/proxy/datacenter/high-risk/IP mismatch +2; Anura suspect +2; phone disagreement +1 or +3; email signals +1 to +3; enrichment disagreement +1 to +3; possible duplicate +1; suspected litigator +2; closed callback window +1. Multiple VPN-related flags contribute one combined +2, rather than repeatedly scoring the same traffic concern.

Decision order: hard stop or 6+ points REJECT; otherwise 2+ points, any unavailable enabled check, or no returned TrustedForm result REVIEW; otherwise 0–1 points ACCEPT. An exact duplicate can reject with zero points.

TrustedForm is required for acceptance, including when disabled. Returned expired/missing status rejects; a missing response reviews. Expiry relies on provider status, not an independent expires_at comparison. The engine never reads expected_verdict hints. Weights/thresholds are explainable code, not calibrated probabilities or configurable policy records.

## Tenancy and authorization

Dashboard/detail queries begin with the signed-in user's account. Only super admins get cross-account scope. Account admins cannot change account_id to manage another tenant. Members are denied pixel management at controller actions.

Ingestion derives the account from the public pixel; sessions resolve through that pixel. Activity requires account scope and the lead-specific bearer token. Full certificate evidence appears only in authenticated tenant-scoped details. Public verification exposes digest/issue metadata and verdict, without submitted fields.

Origin or Referer and page host are allowlisted. Missing origin/referrer is allowed in development/test and refused in production. This is hostname matching, not exact scheme/port origin matching. Headers can be forged outside a browser. CORS permits embedding and does not replace authorization. Tokens currently have no expiry. Signed session proofs/rate limits remain future work.

## Credits and duplicates

Intake locks the account in a transaction. The intersection of account/pixel modules and their complete configured cost is snapshotted. Lead/run creation, balance subtraction and the unique ledger debit commit together. Insufficient funds creates blocked REVIEW, no debit, and no queued work.

Reserve before work to avoid running out mid-check. Rejected/unavailable/failed runs stay charged under this fixed policy; refunds/settlement are not implemented. Past-due accounts can spend existing credits but are warned. Burn is an imported estimate, not recomputed analytics.

Duplicates use account-specific CRM fixtures plus earlier saved leads in the same account. Exact means normalized phone AND email match. A recent phone with another email is possible within 90 days. Current/later records and other accounts are excluded. All prior received leads count, including rejected/reviewed ones; this is an explicit policy choice.

## Jobs and transport

A brief row lock claims queued -> processing. Repeated delivery cannot restart processing/completed/blocked/failed runs. This prevents duplicate delivery, not all failures: a crash can strand processing, and an enqueue failure after debit needs reconciliation. Failed runs are terminal.

Layer results and their activity events commit together. Fixture evaluation errors become unavailable; database/event write failures propagate to the job failure path. On success, certificate, completed verdict and final event commit together.

One background coordinator evaluates layers sequentially. Polling every 500 ms deduplicates event IDs; fast mock work may arrive in one batch. There are no artificial delays. Polling trades more HTTP requests for simple inspection/reconnection. The async adapter is in-process and not durable.

## Certificates

Version 2 snapshots capture session/browser interactions alongside tenant/pixel, page, visit/submit IPs, submitted fields, mock TrustedForm reference when a matching fixture exists, all layer evidence, verdict and issue time. Browser timestamps are labelled browser_reported. Exact consent-text/version capture is not implemented. Unmatched contacts may have no TrustedForm reference and are not accepted without a returned consent check.

SHA-256 hashes recursively key-sorted JSON. Model callbacks block update/delete; they do not stop raw SQL. Digest checks detect evidence changes when the digest is not also changed. A database attacker can rewrite both; this is not a signature or WORM storage. Older version-1 certificates stay unchanged and verifiable. A successful integrity check does not establish legal consent or imply an ACCEPT verdict.

## Answers to design questions

1. Lead owns runs; run owns layer results/certificate; lead owns activity.
2. LayerResult state distinguishes not_enabled, not_applicable, returned and unavailable.
3. Confirmed restrictions/fraud/consent violations are hard stops; uncertain disagreement is weighted.
4. Collect hard-stop reasons and sum weighted risk, then apply the ordered rules above.
5. Missing enabled checks review; independently confirmed rejection still wins.
6. Policy is code. Future audited per-account policy records should be versioned into runs.
7. Start queries from the account/pixel; never trust a browser account ID.
8. Cross-account operator scope is explicit; normal users resolve through their account.
9. Reserve total module cost once per run before scheduling; this makes funds predictable and atomic.
10. Block before starting when cost exceeds balance; warn on past-due/low imported burn coverage.
11. Snapshot checked inputs/reference/results/verdict, timestamp and digest them; explain integrity limits.
12. Background coordination avoids waiting in the request; durability/timeouts/recovery need production work.
13. Polling avoids persistent-connection infrastructure at the cost of requests/latency.
14. First add a durable queue and reconciliation, then versioned policy/provider validation and signed evidence.

## Validation and limitations

Local verification passed with **43 tests, 181 assertions, zero failures, zero errors, and zero skips**. The Rails eager-loading check passed. Browser checks confirmed an ACCEPT result with a saved certificate, valid digest, and a single 17-credit debit; later checks confirmed exact-duplicate REJECT and unmatched-contact REVIEW with a valid certificate. These results cover the tested paths rather than proving all possible inputs or production failure modes.

Other limits: loose provider payload validation; no token expiry; 50-row CRM cap; code-based policy; static burn estimates; seed balances/passwords reset by reseeding; app-level certificate immutability without signatures/retention enforcement; browser/public-pixel spoofing; no automatic stuck-run/refund recovery. Mock fixtures replace vendor contracts. The local helper only adapts imported consent evidence to localhost.
