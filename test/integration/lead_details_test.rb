require "test_helper"

class LeadDetailsTest < ActionDispatch::IntegrationTest
  setup do
    @account = create_account("Detail Account")
    @other_account = create_account("Private Other Account")
    @user = @account.users.create!(
      email: "details-#{SecureRandom.hex(6)}@example.test",
      name: "Detail Member",
      role: "member",
      password: "strong-password"
    )
    @lead = create_lead(@account, "own-detail-lead")
    @foreign_lead = create_lead(@other_account, "foreign-detail-lead")
    @run = @lead.verification_runs.create!(
      state: "completed", verdict: "REVIEW", modules_snapshot: ["trustedform"]
    )
    @run.layer_results.create!(
      layer: "trustedform", state: "unavailable", verdict: "error",
      detail: { "reason" => "Provider unavailable for detail test." }
    )
    @lead.activity_events.create!(
      event_type: "verification_started", payload: { "run_id" => @run.id }
    )
    @certificate = ConsentCertificate.new(
      lead: @lead, verification_run: @run,
      certificate_id: "cert_#{SecureRandom.hex(16)}",
      evidence: { "verdict" => { "verdict" => "REVIEW" } }
    )
    @certificate.sha256 = Digest::SHA256.hexdigest(@certificate.canonical_evidence)
    @certificate.save!
  end

  test "member can inspect own layers certificate and timeline" do
    sign_in(@user)
    get "/leads/#{@lead.id}"

    assert_response :success
    assert_select "#layer-results", text: /Provider unavailable for detail test/
    assert_select "#consent-certificate", text: /#{@certificate.certificate_id}/
    assert_select "#activity-timeline", text: /Verification started/
  end

  test "member cannot open another account lead by its ID" do
    sign_in(@user)
    get "/leads/#{@foreign_lead.id}"

    assert_response :not_found
    assert_no_match(/foreign-detail-lead|Private Other Account/, response.body)
  end

  test "lead details require sign in" do
    get "/leads/#{@lead.id}"

    assert_redirected_to "/login"
  end

  test "super admin can inspect another account lead without a run" do
    admin = User.create!(
      email: "detail-admin-#{SecureRandom.hex(6)}@example.test",
      name: "Detail Admin", role: "super_admin",
      password: "strong-password"
    )
    sign_in(admin)
    get "/leads/#{@foreign_lead.id}"

    assert_response :success
    assert_select "h1", text: /foreign-detail-lead/
    assert_match "No verification run exists yet.", response.body
  end

  private

  def sign_in(user)
    post "/login", params: {
      email: user.email, password: "strong-password"
    }
    assert_response :redirect
  end

  def create_account(name)
    Account.create!(
      external_id: "details-#{SecureRandom.hex(6)}",
      name: name, plan: "starter", status: "active"
    )
  end

  def create_lead(account, external_id)
    pixel = account.pixels.create!(
      name: "Detail Pixel", allowed_hosts: ["localhost"]
    )
    account.leads.create!(
      pixel: pixel, external_id: external_id,
      fields: { "first_name" => "Detail", "email" => "detail@example.test" }
    )
  end
end
