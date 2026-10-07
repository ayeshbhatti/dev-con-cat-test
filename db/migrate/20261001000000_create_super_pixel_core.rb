class CreateSuperPixelCore < ActiveRecord::Migration[7.1]
  def change
    create_table :accounts do |t|
      t.string :external_id, null: false
      t.string :name, null: false
      t.string :plan, null: false
      t.string :status, null: false, default: "active"
      t.integer :monthly_credit_allowance, null: false, default: 0
      t.integer :credits_used_this_cycle, null: false, default: 0
      t.integer :credits_remaining, null: false, default: 0
      t.integer :avg_daily_burn, null: false, default: 0
      t.jsonb :enabled_modules, null: false, default: []
      t.jsonb :module_costs, null: false, default: {}
      t.date :cycle_start
      t.date :cycle_end
      t.timestamps
    end
    add_index :accounts, :external_id, unique: true

    create_table :users do |t|
      t.references :account, foreign_key: true
      t.string :external_id
      t.string :name, null: false
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :role, null: false
      t.timestamps
    end
    add_index :users, :email, unique: true
    add_index :users, :external_id, unique: true

    create_table :pixels do |t|
      t.references :account, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :name, null: false
      t.jsonb :allowed_hosts, null: false, default: []
      t.jsonb :enabled_modules, null: false, default: []
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :pixels, :public_id, unique: true

    create_table :capture_sessions do |t|
      t.references :pixel, null: false, foreign_key: true, index: false
      t.string :session_id, null: false
      t.string :page_url, null: false
      t.string :referrer
      t.string :visitor_ip
      t.string :user_agent
      t.datetime :started_at, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :capture_sessions, :session_id, unique: true

    create_table :leads do |t|
      t.references :account, null: false, foreign_key: true
      t.references :pixel, null: false, foreign_key: true
      t.references :capture_session, foreign_key: true, index: false
      t.string :external_id, null: false
      t.string :landing_page_url
      t.string :campaign
      t.string :submit_ip
      t.string :user_agent
      t.string :activity_token_digest
      t.integer :form_dwell_ms
      t.jsonb :fields, null: false, default: {}
      t.timestamps
    end
    add_index :leads, %i[account_id external_id], unique: true
    add_index :leads, %i[account_id created_at]
    add_index :leads, :capture_session_id, unique: true

    create_table :verification_runs do |t|
      t.references :lead, null: false, foreign_key: true
      t.string :state, null: false, default: "queued"
      t.string :verdict
      t.integer :score
      t.jsonb :reasons, null: false, default: []
      t.jsonb :modules_snapshot, null: false, default: []
      t.integer :reserved_credits, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    create_table :layer_results do |t|
      t.references :verification_run, null: false, foreign_key: true
      t.string :layer, null: false
      t.string :state, null: false
      t.string :verdict
      t.jsonb :detail, null: false, default: {}
      t.datetime :completed_at
      t.timestamps
    end
    add_index :layer_results, %i[verification_run_id layer], unique: true

    create_table :consent_certificates do |t|
      t.references :lead, null: false, foreign_key: true
      t.references :verification_run, null: false, foreign_key: true
      t.string :certificate_id, null: false
      t.string :sha256, null: false
      t.jsonb :evidence, null: false
      t.timestamps
    end
    add_index :consent_certificates, :certificate_id, unique: true
    add_index :consent_certificates, :sha256, unique: true

    create_table :activity_events do |t|
      t.references :lead, null: false, foreign_key: true
      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
    add_index :activity_events, %i[lead_id created_at]

    create_table :credit_ledger_entries do |t|
      t.references :account, null: false, foreign_key: true
      t.references :verification_run, foreign_key: true
      t.integer :amount, null: false
      t.string :reason, null: false
      t.string :idempotency_key, null: false
      t.timestamps
    end
    add_index :credit_ledger_entries, :idempotency_key, unique: true

    create_table :provider_datasets do |t|
      t.string :name, null: false
      t.jsonb :data, null: false
      t.timestamps
    end
    add_index :provider_datasets, :name, unique: true
  end
end
