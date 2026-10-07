require "test_helper"

class LeadIntakeTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(external_id: "acct-intake", name: "Intake", plan: "starter", status: "active",
                               enabled_modules: ["anura"], module_costs: { "anura" => 2 }, credits_remaining: 5)
    @pixel = @account.pixels.create!(name: "Test", allowed_hosts: ["localhost"], enabled_modules: ["anura"])
    @capture = @pixel.capture_sessions.create!(session_id: "session-#{SecureRandom.hex(4)}", page_url: "https://localhost/form",
                                               started_at: Time.current)
  end

  test "reserves configured module credits exactly once before scheduling the run" do
    lead, run, token = intake.call
    @account.reload

    assert_equal 3, @account.credits_remaining
    assert_equal(-2, @account.credit_ledger_entries.sole.amount)
    assert_equal 2, run.reserved_credits
    assert_equal "queued", run.state
    assert lead.activity_token_valid?(token)
  end

  test "insufficient balance blocks the run without a partial debit" do
    @account.update!(credits_remaining: 1)
    lead, run, token = intake.call

    assert_equal "blocked", run.state
    assert_equal "REVIEW", run.verdict
    assert_equal 1, @account.reload.credits_remaining
    assert_empty @account.credit_ledger_entries
    assert_equal "final_verdict", lead.activity_events.sole.event_type
    assert lead.activity_token_valid?(token)
  end

  private

  def intake
    LeadIntake.new(pixel: @pixel, capture_session: @capture,
                   fields: { "first_name" => "A", "last_name" => "B", "email" => "a@example.test", "phone" => "+15555550142", "consent" => true },
                   submit_ip: "127.0.0.1", user_agent: "test", dwell_ms: 1200)
  end
end
