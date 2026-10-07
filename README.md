# Super Pixel

A Ruby on Rails and PostgreSQL application for capturing leads, running mock fraud and consent checks, and producing an explained verdict and an evidence certificate. It includes account isolation, role-based access, verification credits, a searchable lead dashboard, and a landing page connected to the backend through polling.

The supplied assignment and mock datasets are retained. The original starter README is preserved in [docs/STARTER_README.md](docs/STARTER_README.md).

## First-time setup

Tested with Ruby 3.3.1 and Rails 7.1.6. Install Bundler and PostgreSQL, and use a PostgreSQL role with permission to create databases. Run the commands below from the repository root.

For Ubuntu/WSL with an existing PostgreSQL role matching your Linux username:

~~~bash
sudo service postgresql start
export PGUSER="$(whoami)"
export PGHOST=/var/run/postgresql
unset PGPASSWORD

bundle install
bundle exec rails db:create db:migrate
SEED_PASSWORD='choose-a-local-demo-password' bundle exec rails db:seed
bundle exec rails server
~~~

Replace `choose-a-local-demo-password` with a local password. If your PostgreSQL role has a different name, set `PGUSER` accordingly. For a TCP connection, configure `PGHOST`, `PGUSER`, and `PGPASSWORD` for that role instead. Apply the connection settings in each terminal that runs database commands.

Seed once to initialize the demo. Without `SEED_PASSWORD`, seeding prints a generated password shared by the demo users. Reseeding resets the imported account balances and user passwords; it does not reconcile the credit ledger. Seeded historical runs do not debit credits because the supplied balances are imported snapshots.

## Application

| Surface | URL/action |
| --- | --- |
| Dashboard | http://localhost:3000/ |
| Backend demo | http://localhost:3000/demo.html |
| Pixel management | Manage pixels as account admin/super admin |
| Lead details | Click a lead ID |
| Certificate verification | Follow a lead's certificate link |

Demo users share the password chosen or printed during seeding:

| Email | Role |
| --- | --- |
| `admin@catchingconsent.example` | Super admin |
| `dana@solarpro.example` | Account admin |
| `luis@solarpro.example` | Member |

Search covers name, email, phone, and lead ID. Verdict filters use the latest verification run. Super admins can filter accounts; members and account admins see only their own account. Results are capped at 50 without pagination.

## Demo scenarios

Open [http://localhost:3000/demo.html](http://localhost:3000/demo.html) through the running Rails server. The page uses pixel `px_9f2a01` and the real Rails API. Field interactions are recorded, and verification activity is fetched from persisted backend events.

To align Maria's imported consent fixture with the local page:

~~~bash
bundle exec rails runner script/setup_local_demo.rb
~~~

This development-only helper adapts the imported TrustedForm database record for `L-1001` to `http://localhost:3000/demo.html`. It leaves the supplied JSON files and existing certificates unchanged. Page matching and consensus rules still apply.

Useful checks:

- **Known contact:** submit Maria Gonzalez, `maria.gonzalez@gmail.com`, and `+13105550142` with consent. The contact matches provider fixtures. After the helper, TrustedForm should pass, but Maria already exists in the seeded account, so duplicate detection produces an exact match and the final verdict is `REJECT`.
- **Unmatched contact:** use an unused pair such as `new-demo@example.test` and `+15555550199`. Enabled provider checks without matching fixtures are explicitly unavailable, so the verdict is `REVIEW` unless another rejection condition applies. Repeating the pair can produce an exact-duplicate rejection.
- **Missing consent:** the API returns `consent_required` without creating a lead or charging credits. The demo form also requires its consent checkbox.
- **Certificate:** open the saved lead in the dashboard and follow its verification link. `valid: true` means the stored evidence matches its digest; it does not mean the lead was accepted or consent was independently proven.

Refresh before each new demo submission: a capture session can create only one lead. Existing certificates preserve the evidence and verdict from their original run.

## Tests and verification

Configure the database in the test terminal, then run:

~~~bash
bundle exec rails test
bundle exec rails zeitwerk:check
~~~

Verified locally: **43 tests, 181 assertions, zero failures, zero errors, and zero skips**. The Rails eager-loading check also passed. Tests cover consensus, credits, account isolation, search, duplicate detection, role/API boundaries, repeated submissions and job delivery, capture evidence, atomic layer/event writes, and certificate integrity and public-field privacy.

## Implementation boundaries

Rails routes and sessions, database persistence, background jobs, consensus calculation, certificates and digests, credit transactions, search, and polling are implemented. Vendor responses, initial buyer CRM records, plan data, and burn estimates come from the supplied mock datasets; no real vendor or billing API is called.

The standalone example retains a simulation fallback when no endpoint is configured. The served `/demo.html` explicitly uses the Rails endpoint. Activity tokens are specific to a lead and stored as digests, but do not currently expire. The background queue runs in-process and is not durable.

See [SOLUTION.md](SOLUTION.md) for architectural decisions, answers to the design questions, and known limitations. The first production improvements would be a durable queue with reconciliation, stricter provider validation, and stronger certificate protection.
