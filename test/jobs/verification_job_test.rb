require "test_helper"

class VerificationJobTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(
      external_id: "job-#{SecureRandom.hex(6)}",
      name: "Job Test",
      plan: "starter",
      status: "active"
    )

    @pixel = @account.pixels.create!(
      name: "Job Pixel",
      allowed_hosts: ["localhost"]
    )

    @lead = @account.leads.create!(
      pixel: @pixel,
      external_id: "lead-#{SecureRandom.hex(6)}",
      landing_page_url: "http://localhost/demo.html",
      fields: {
        "email" => "job@example.test",
        "phone" => "+15555550142",
        "consent" => true
      }
    )

    @run = @lead.verification_runs.create!(
      state: "queued",
      modules_snapshot: ["trustedform"]
    )
  end

  test "repeating a completed job preserves results and certificate" do
    VerificationJob.perform_now(@run.id)

    assert_equal "completed", @run.reload.state
    assert_equal "REVIEW", @run.verdict

    before = @run.attributes
    layer_ids = @run.layer_results.order(:id).pluck(:id)
    event_ids = @lead.activity_events.order(:id).pluck(:id)
    certificate = @run.consent_certificate
    assert certificate.valid_evidence?
    assert_equal VerificationJob::LAYERS.size, layer_ids.size

    VerificationJob.perform_now(@run.id)

    assert_equal before, @run.reload.attributes
    assert_equal layer_ids, @run.layer_results.order(:id).pluck(:id)
    assert_equal event_ids, @lead.activity_events.order(:id).pluck(:id)
    assert_equal 1, @lead.consent_certificates.count
    assert_equal certificate.id, @run.consent_certificate.id
    assert_equal certificate.sha256, @run.consent_certificate.sha256
  end

  test "a job already being processed is not started again" do
    @run.update!(state: "processing", started_at: Time.current)
    before = @run.attributes

    VerificationJob.perform_now(@run.id)

    assert_equal before, @run.reload.attributes
    assert_empty @run.layer_results
    assert_empty @lead.activity_events
    assert_empty @lead.consent_certificates
  end

  test "blocked and failed runs are not restarted" do
    %w[blocked failed].each do |state|
      @run.update!(state: state, verdict: "REVIEW")
      before = @run.attributes

      VerificationJob.perform_now(@run.id)

      assert_equal before, @run.reload.attributes
      assert_empty @run.layer_results
      assert_empty @lead.activity_events
      assert_empty @lead.consent_certificates
    end
  end
end
