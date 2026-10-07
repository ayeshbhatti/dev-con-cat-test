# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_10_01_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "name", null: false
    t.string "plan", null: false
    t.string "status", default: "active", null: false
    t.integer "monthly_credit_allowance", default: 0, null: false
    t.integer "credits_used_this_cycle", default: 0, null: false
    t.integer "credits_remaining", default: 0, null: false
    t.integer "avg_daily_burn", default: 0, null: false
    t.jsonb "enabled_modules", default: [], null: false
    t.jsonb "module_costs", default: {}, null: false
    t.date "cycle_start"
    t.date "cycle_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_accounts_on_external_id", unique: true
  end

  create_table "activity_events", force: :cascade do |t|
    t.bigint "lead_id", null: false
    t.string "event_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lead_id", "created_at"], name: "index_activity_events_on_lead_id_and_created_at"
    t.index ["lead_id"], name: "index_activity_events_on_lead_id"
  end

  create_table "capture_sessions", force: :cascade do |t|
    t.bigint "pixel_id", null: false
    t.string "session_id", null: false
    t.string "page_url", null: false
    t.string "referrer"
    t.string "visitor_ip"
    t.string "user_agent"
    t.datetime "started_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_capture_sessions_on_session_id", unique: true
  end

  create_table "consent_certificates", force: :cascade do |t|
    t.bigint "lead_id", null: false
    t.bigint "verification_run_id", null: false
    t.string "certificate_id", null: false
    t.string "sha256", null: false
    t.jsonb "evidence", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["certificate_id"], name: "index_consent_certificates_on_certificate_id", unique: true
    t.index ["lead_id"], name: "index_consent_certificates_on_lead_id"
    t.index ["sha256"], name: "index_consent_certificates_on_sha256", unique: true
    t.index ["verification_run_id"], name: "index_consent_certificates_on_verification_run_id"
  end

  create_table "credit_ledger_entries", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "verification_run_id"
    t.integer "amount", null: false
    t.string "reason", null: false
    t.string "idempotency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_credit_ledger_entries_on_account_id"
    t.index ["idempotency_key"], name: "index_credit_ledger_entries_on_idempotency_key", unique: true
    t.index ["verification_run_id"], name: "index_credit_ledger_entries_on_verification_run_id"
  end

  create_table "layer_results", force: :cascade do |t|
    t.bigint "verification_run_id", null: false
    t.string "layer", null: false
    t.string "state", null: false
    t.string "verdict"
    t.jsonb "detail", default: {}, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["verification_run_id", "layer"], name: "index_layer_results_on_verification_run_id_and_layer", unique: true
    t.index ["verification_run_id"], name: "index_layer_results_on_verification_run_id"
  end

  create_table "leads", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "pixel_id", null: false
    t.bigint "capture_session_id"
    t.string "external_id", null: false
    t.string "landing_page_url"
    t.string "campaign"
    t.string "submit_ip"
    t.string "user_agent"
    t.string "activity_token_digest"
    t.integer "form_dwell_ms"
    t.jsonb "fields", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_leads_on_account_id_and_created_at"
    t.index ["account_id", "external_id"], name: "index_leads_on_account_id_and_external_id", unique: true
    t.index ["account_id"], name: "index_leads_on_account_id"
    t.index ["capture_session_id"], name: "index_leads_on_capture_session_id", unique: true
    t.index ["pixel_id"], name: "index_leads_on_pixel_id"
  end

  create_table "pixels", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "public_id", null: false
    t.string "name", null: false
    t.jsonb "allowed_hosts", default: [], null: false
    t.jsonb "enabled_modules", default: [], null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_pixels_on_account_id"
    t.index ["public_id"], name: "index_pixels_on_public_id", unique: true
  end

  create_table "provider_datasets", force: :cascade do |t|
    t.string "name", null: false
    t.jsonb "data", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_provider_datasets_on_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.bigint "account_id"
    t.string "external_id"
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["external_id"], name: "index_users_on_external_id", unique: true
  end

  create_table "verification_runs", force: :cascade do |t|
    t.bigint "lead_id", null: false
    t.string "state", default: "queued", null: false
    t.string "verdict"
    t.integer "score"
    t.jsonb "reasons", default: [], null: false
    t.jsonb "modules_snapshot", default: [], null: false
    t.integer "reserved_credits", default: 0, null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lead_id"], name: "index_verification_runs_on_lead_id"
  end

  add_foreign_key "activity_events", "leads"
  add_foreign_key "capture_sessions", "pixels"
  add_foreign_key "consent_certificates", "leads"
  add_foreign_key "consent_certificates", "verification_runs"
  add_foreign_key "credit_ledger_entries", "accounts"
  add_foreign_key "credit_ledger_entries", "verification_runs"
  add_foreign_key "layer_results", "verification_runs"
  add_foreign_key "leads", "accounts"
  add_foreign_key "leads", "capture_sessions"
  add_foreign_key "leads", "pixels"
  add_foreign_key "pixels", "accounts"
  add_foreign_key "users", "accounts"
  add_foreign_key "verification_runs", "leads"
end
