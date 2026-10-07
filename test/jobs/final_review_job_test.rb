require "test_helper"
require "minitest/mock"

class FinalReviewJobTest < ActiveSupport::TestCase
  setup do
    account = Account.create!(external_id: "final-job", name: "Final Job", plan: "starter", status: "active")
    pixel = account.pixels.create!(name: "Final Job Pixel", allowed_hosts: ["localhost"])
    @capture = pixel.capture_sessions.create!(session_id: "final-job-session", page_url: "https://localhost/form", started_at: Time.current,
                                              metadata: { "interactions" => [{ "name" => "email", "action" => "focus", "at" => Time.current.iso8601 }] })
    @lead = account.leads.create!(pixel: pixel, capture_session: @capture, external_id: "final-job-lead", landing_page_url: @capture.page_url,
                                  fields: { "email" => "final@example.test", "consent" => true })
    @run = @lead.verification_runs.create!(state: "queued", modules_snapshot: [])
  end

  test "layer result rolls back when its activity event cannot be saved" do
    ActivityEvent.stub(:create!, ->(*) { raise "event-write failed" }) do
      assert_no_difference "LayerResult.count" do
        error = assert_raises(RuntimeError) do
          VerificationJob.new.send(:persist_layer, @run, "anura", MockFixtureLookup.new(@lead))
        end
        assert_equal "event-write failed", error.message
      end
    end
  end

  test "certificate retains a snapshot of browser capture evidence" do
    VerificationJob.perform_now(@run.id)
    certificate = @run.reload.consent_certificate
    assert_equal 2, certificate.evidence["version"]
    assert_equal @capture.session_id, certificate.evidence.dig("capture_session", "session_id")
    assert_equal "focus", certificate.evidence.dig("capture_session", "interactions", 0, "action")
    @capture.update!(metadata: { "interactions" => [] })
    assert_equal 1, certificate.reload.evidence.dig("capture_session", "interactions").size
    assert certificate.valid_evidence?
  end
end
