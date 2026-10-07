require "test_helper"

class PixelBoundaryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @account = Account.create!(external_id: "boundary-a", name: "Boundary A", plan: "starter", status: "active",
                               enabled_modules: ["anura"], module_costs: { "anura" => 2 }, credits_remaining: 5)
    @other_account = Account.create!(external_id: "boundary-b", name: "Boundary B", plan: "starter", status: "active", credits_remaining: 5)
    @pixel = @account.pixels.create!(name: "Boundary Pixel A", allowed_hosts: ["localhost"], enabled_modules: ["anura"])
    @other_pixel = @other_account.pixels.create!(name: "Boundary Pixel B", allowed_hosts: ["localhost"])
    @capture = @pixel.capture_sessions.create!(session_id: "boundary-session-a", page_url: "https://localhost/form", started_at: Time.current)
    @other_capture = @other_pixel.capture_sessions.create!(session_id: "boundary-session-b", page_url: "https://localhost/form", started_at: Time.current)
    @headers = { "Origin" => "https://localhost" }
  end

  test "visit retry preserves original evidence and recorded interactions" do
    visit = { pixel_id: @pixel.public_id, session_id: "retry-session", page_url: "https://localhost/form", started_at: Time.current.iso8601 }
    post "/api/pixel/visit", params: visit, headers: @headers, as: :json
    assert_response :accepted
    capture = @pixel.capture_sessions.find_by!(session_id: "retry-session")
    capture.update!(metadata: { "interactions" => [{ "name" => "email", "action" => "focus", "at" => Time.current.iso8601 }] })
    before = capture.attributes

    post "/api/pixel/visit", params: visit.merge(page_url: "https://localhost/another-page"), headers: @headers, as: :json
    assert_response :accepted
    assert_equal before, capture.reload.attributes
  end

  test "disallowed origin cannot write a visit" do
    assert_no_difference "CaptureSession.count" do
      post "/api/pixel/visit", params: { pixel_id: @pixel.public_id, session_id: "bad-origin", page_url: "https://localhost/form" },
           headers: { "Origin" => "https://unapproved.example" }, as: :json
    end
    assert_response :forbidden
  end

  test "a pixel cannot submit another pixel capture session" do
    assert_no_difference "Lead.count" do
      post "/api/pixel/leads", params: payload.merge(session_id: @other_capture.session_id), headers: @headers, as: :json
    end
    assert_response :not_found
    assert_equal 5, @account.reload.credits_remaining
    assert_equal 5, @other_account.reload.credits_remaining
  end

  test "intake derives tenant from pixel and ignores browser account ID" do
    assert_enqueued_jobs 1, only: VerificationJob do
      post "/api/pixel/leads", params: payload.merge(account_id: @other_account.id), headers: @headers, as: :json
    end
    assert_response :created
    lead = @account.leads.find_by!(external_id: response.parsed_body.fetch("lead_id"))
    assert_equal @account.id, lead.account_id
    assert_empty @other_account.leads
    assert_equal 3, @account.reload.credits_remaining
    assert_equal 5, @other_account.reload.credits_remaining
  end

  test "replaying a successful submission does not debit twice" do
    post "/api/pixel/leads", params: payload, headers: @headers, as: :json
    assert_response :created
    assert_no_difference ["Lead.count", "CreditLedgerEntry.count"] do
      assert_enqueued_jobs 0 do
        post "/api/pixel/leads", params: payload, headers: @headers, as: :json
      end
    end
    assert_response :conflict
    assert_equal 3, @account.reload.credits_remaining
  end

  test "consent rejection causes no lead debit or job" do
    data = payload
    data[:fields] = data[:fields].merge(consent: false)
    assert_no_difference ["Lead.count", "CreditLedgerEntry.count"] do
      assert_enqueued_jobs 0 do
        post "/api/pixel/leads", params: data, headers: @headers, as: :json
      end
    end
    assert_response :unprocessable_entity
    assert_equal "consent_required", response.parsed_body["error"]
    assert_equal 5, @account.reload.credits_remaining
  end

  test "activity requires the returned lead token" do
    post "/api/pixel/leads", params: payload, headers: @headers, as: :json
    assert_response :created
    data = response.parsed_body
    path = "/api/pixel/leads/#{data.fetch('lead_id')}/activity"
    get path, params: { pixel_id: @pixel.public_id }, headers: @headers
    assert_response :forbidden
    get path, params: { pixel_id: @pixel.public_id }, headers: @headers.merge("Authorization" => "Bearer #{data.fetch('activity_token')}")
    assert_response :success
    assert_equal "queued", response.parsed_body["state"]
  end

  private

  def payload
    { pixel_id: @pixel.public_id, session_id: @capture.session_id, form_dwell_ms: 1200,
      fields: { first_name: "Boundary", last_name: "Test", email: "boundary@example.test", phone: "+15555550142", consent: true } }
  end
end
