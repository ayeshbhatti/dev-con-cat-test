# Super Pixel — Rails take-home

Rails/PostgreSQL lead capture with tenant login, mock fraud/consent checks, explained verdicts, certificates, credits, a searchable CRM, and a backend-connected polling demo.

## First-time setup

Use Ruby 3.3.1 (Gemfile.lock), Bundler, PostgreSQL, and a role allowed to create databases.

For Ubuntu/WSL with an existing role matching your Linux username:

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

Replace the sample password. TCP/password users should instead configure PGHOST, PGUSER and PGPASSWORD for their existing role. Every new terminal needs its connection settings.

Seed once when initializing demo data. Reseeding resets fixture account balances and user passwords; it is not ledger reconciliation. Historical seed runs do not debit credits: balances are imported snapshots. Without SEED_PASSWORD, seeding prints a random password shared by demo users.

Existing installations applying the final review patch need no migration or reseed.

## Application

| Surface | URL/action |
| --- | --- |
| Dashboard | http://localhost:3000/ |
| Backend demo | http://localhost:3000/demo.html |
| Pixel management | Manage pixels as account admin/super admin |
| Lead details | Click a lead ID |
| Certificate verification | Follow a lead's certificate link |

Users: admin@catchingconsent.example (super admin), dana@solarpro.example (account admin), luis@solarpro.example (member). Use the password chosen/printed at seeding.

Search covers name, email, phone and lead ID. Verdict filters use the latest run. Super admins can filter accounts; members/account admins stay within their account. Results cap at 50 without pagination.

## Demo scenarios

Use localhost rather than opening the HTML as a file. The served page uses pixel px_9f2a01.

To align Maria's imported consent fixture with the local page:

~~~bash
bundle exec rails runner script/setup_local_demo.rb
~~~

This development-only helper changes the imported TrustedForm database record for L-1001, leaving the supplied JSON and issued certificates unchanged. It does not disable page matching or override consensus.

Submit Maria Gonzalez, maria.gonzalez@gmail.com, +13105550142 with consent. Maria already exists in the seeded account, so the current detector should show exact duplicate / REJECT. TrustedForm should pass after the helper. Seed/earlier ACCEPT certificates retain their original evidence.

An unused email/phone pair such as new-demo@example.test and +15555550199 produces explicit unavailable provider results and REVIEW. No mocked pass is invented for unmatched input. Missing consent returns consent_required without creating a lead or charging credits.

Refresh before each new demo lead: a capture session may create only one lead.

## Tests and verification

Configure the database in the test terminal, then run:

~~~bash
bundle exec rails test
bundle exec rails zeitwerk:check
~~~

The candidate confirmed the uploaded snapshot at 29 tests, 111 assertions, zero failures/errors. The final review adds 14 tests for API/role boundaries, replay, visit preservation, atomic result/event writes, capture snapshots and public certificate privacy. Final tests must run locally: the review workspace had no Ruby/PostgreSQL runtime.

Real components: Rails routes/sessions, PostgreSQL, jobs, verdict calculation, certificates/digests, credit transactions, search, and polling. Mock components: vendor responses, initial CRM records, plans and burn estimates.

The example retains a simulation fallback without a configured endpoint. The served /demo.html explicitly uses the Rails endpoint. Activity tokens are lead-specific and stored as digests but currently do not expire. The async queue is in-process and not durable.

See SOLUTION.md for policy, design answers and limitations.
