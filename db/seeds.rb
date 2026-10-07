require "json"
require "securerandom"

fixture_root = Rails.root.join("mock-data")
load_json = ->(path) { JSON.parse(File.read(path)) }
accounts_data = load_json.call(fixture_root.join("accounts.json"))
costs = accounts_data.fetch("module_costs_in_credits")

accounts_data.fetch("accounts").each do |row|
  account = Account.find_or_initialize_by(external_id: row.fetch("account_id"))
  account.assign_attributes(name: row.fetch("company_name"), plan: row.fetch("plan"), status: row.fetch("status"),
                            monthly_credit_allowance: row.fetch("monthly_credit_allowance"),
                            credits_used_this_cycle: row.fetch("credits_used_this_cycle"), credits_remaining: row.fetch("credits_remaining"),
                            avg_daily_burn: row.fetch("avg_daily_burn"), enabled_modules: row.fetch("enabled_modules"),
                            module_costs: costs, cycle_start: row["cycle_start"], cycle_end: row["cycle_end"])
  account.save!
end

demo_password = ENV["SEED_PASSWORD"].presence || SecureRandom.base64(15)
load_json.call(fixture_root.join("users.json")).fetch("users").each do |row|
  user = User.find_or_initialize_by(email: row.fetch("email").downcase)
  user.assign_attributes(external_id: row.fetch("user_id"), name: row.fetch("name"), role: row.fetch("role"),
                         account: Account.find_by(external_id: row["account_id"]), password: demo_password,
                         password_confirmation: demo_password)
  user.save!
end

%w[leads buyers_crm].each do |name|
  ProviderDataset.find_or_create_by!(name: name) { |dataset| dataset.data = load_json.call(fixture_root.join("#{name}.json")) }
end
Dir[fixture_root.join("providers/*.json")].sort.each do |path|
  name = File.basename(path, ".json")
  ProviderDataset.find_or_create_by!(name: name) { |dataset| dataset.data = load_json.call(path) }
end

lead_data = load_json.call(fixture_root.join("leads.json")).fetch("leads")
lead_data.each do |row|
  account = Account.find_by!(external_id: row.fetch("account_id"))
  host = URI.parse(row.fetch("landing_page_url")).host
  pixel = Pixel.find_or_create_by!(public_id: row.fetch("pixel_id")) do |record|
    record.account = account
    record.name = "#{account.name} demo pixel"
    record.allowed_hosts = [host, "localhost", "127.0.0.1"]
    record.enabled_modules = account.enabled_modules
  end
  capture = CaptureSession.find_or_create_by!(session_id: "seed-#{row.fetch('lead_id')}") do |record|
    record.pixel = pixel
    record.page_url = row.fetch("landing_page_url")
    record.visitor_ip = row["ip_address"]
    record.user_agent = row["user_agent"]
    record.started_at = Time.zone.parse(row.fetch("captured_at")) - row.fetch("form_dwell_ms", 0).to_i / 1000.0
  end
  lead = account.leads.find_or_create_by!(external_id: row.fetch("lead_id")) do |record|
    record.pixel = pixel
    record.capture_session = capture
    record.landing_page_url = row["landing_page_url"]
    record.submit_ip = row["ip_address"]
    record.user_agent = row["user_agent"]
    record.form_dwell_ms = row["form_dwell_ms"]
    record.created_at = Time.zone.parse(row.fetch("captured_at"))
    record.updated_at = Time.zone.parse(row.fetch("captured_at"))
    record.fields = { "first_name" => row["first_name"], "last_name" => row["last_name"], "email" => row["email"],
                      "phone" => row["phone"], "consent" => true, "trusted_form_cert_url" => row["trusted_form_cert_url"] }
  end
  next if lead.verification_runs.exists?
  run = lead.verification_runs.create!(modules_snapshot: account.enabled_modules, state: "queued")
  VerificationJob.perform_now(run.id)
end

puts "Demo users are seeded. Temporary shared demo password: #{demo_password}"
puts "For a stable local password, rerun with SEED_PASSWORD='your-local-password' bin/rails db:seed"
