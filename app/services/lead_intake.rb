require "digest"
require "securerandom"

class LeadIntake
  def initialize(pixel:, capture_session:, fields:, submit_ip:, user_agent:, dwell_ms:)
    @pixel, @capture_session, @fields = pixel, capture_session, fields
    @submit_ip, @user_agent, @dwell_ms = submit_ip, user_agent, dwell_ms
  end

  def call
    lead = nil
    run = nil
    insufficient = false
    activity_token = SecureRandom.urlsafe_base64(32)
    @pixel.account.with_lock do
      account = @pixel.account
      modules = (@pixel.enabled_modules & account.enabled_modules).uniq
      cost = modules.sum { |name| account.module_costs.fetch(name, 0).to_i }
      lead = account.leads.create!(pixel: @pixel, capture_session: @capture_session, external_id: "L-#{SecureRandom.hex(8)}",
                                  landing_page_url: @capture_session.page_url, submit_ip: @submit_ip,
                                  user_agent: @user_agent, form_dwell_ms: @dwell_ms, fields: @fields,
                                  activity_token_digest: Digest::SHA256.hexdigest(activity_token))
      run = lead.verification_runs.create!(modules_snapshot: modules, reserved_credits: cost)

      if account.credits_remaining < cost
        run.update!(state: "blocked", verdict: "REVIEW", score: 0, reasons: ["Verification not run: account has insufficient credits."])
        event(lead, "final_verdict", verdict: "REVIEW", score: 0, reasons: run.reasons)
        insufficient = true
        next
      end

      account.update!(credits_remaining: account.credits_remaining - cost, credits_used_this_cycle: account.credits_used_this_cycle + cost)
      account.credit_ledger_entries.create!(verification_run: run, amount: -cost, reason: "verification_reserved", idempotency_key: "verification-run:#{run.id}") if cost.positive?
      event(lead, "lead_received", lead_id: lead.external_id)
    end
    VerificationJob.perform_later(run.id) unless insufficient
    [lead, run, activity_token]
  end

  private

  def event(lead, type, payload = {})
    lead.activity_events.create!(event_type: type, payload: payload)
  end
end
