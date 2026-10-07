require "test_helper"

class DashboardSearchTest < ActionDispatch::IntegrationTest
  setup do
    @account = create_account("Search Account")
    @other_account = create_account("Other Account")
    @user = @account.users.create!(
      email: "search-#{SecureRandom.hex(6)}@example.test",
      name: "Search Member",
      role: "member",
      password: "strong-password"
    )

    @own_lead = create_lead(@account, "own-search-lead", "ACCEPT")
    @review_lead = create_lead(@account, "own-review-lead", "REVIEW")
    @foreign_lead = create_lead(@other_account, "foreign-search-lead", "ACCEPT")

    post "/login", params: {
      email: @user.email,
      password: "strong-password"
    }
    assert_response :redirect
  end

  test "search finds own leads without exposing another account" do
    get "/", params: {
      q: "maria.gonzalez",
      account_id: @other_account.id
    }

    assert_response :success
    assert_select "tbody code", text: @own_lead.external_id
    assert_select "tbody code", text: @foreign_lead.external_id, count: 0
  end

  test "search supports a full name" do
    get "/", params: { q: "Maria Gonzalez" }

    assert_response :success
    assert_select "tbody code", text: @own_lead.external_id
    assert_select "tbody code", text: @foreign_lead.external_id, count: 0
  end

  test "verdict filtering uses the latest run" do
    @own_lead.verification_runs.create!(
      state: "completed",
      verdict: "REJECT",
      modules_snapshot: [],
      created_at: 1.day.ago
    )

    get "/", params: { verdict: "ACCEPT" }

    assert_response :success
    assert_select "tbody code", text: @own_lead.external_id
    assert_select "tbody code", text: @review_lead.external_id, count: 0
    assert_select "tbody code", text: @foreign_lead.external_id, count: 0
  end

  test "super admin can filter by account" do
    admin = User.create!(
      email: "search-admin-#{SecureRandom.hex(6)}@example.test",
      name: "Search Admin",
      role: "super_admin",
      password: "strong-password"
    )
    post "/login", params: {
      email: admin.email,
      password: "strong-password"
    }

    get "/", params: { account_id: @other_account.id }

    assert_response :success
    assert_select "tbody code", text: @foreign_lead.external_id
    assert_select "tbody code", text: @own_lead.external_id, count: 0
  end

  private

  def create_account(name)
    Account.create!(
      external_id: "search-#{SecureRandom.hex(6)}",
      name: name,
      plan: "starter",
      status: "active"
    )
  end

  def create_lead(account, external_id, verdict)
    pixel = account.pixels.create!(
      name: "Search Pixel",
      allowed_hosts: ["localhost"]
    )
    lead = account.leads.create!(
      pixel: pixel,
      external_id: external_id,
      fields: {
        "first_name" => "Maria",
        "last_name" => "Gonzalez",
        "email" => "maria.gonzalez@example.test",
        "phone" => "+15555550142"
      }
    )
    lead.verification_runs.create!(
      state: "completed",
      verdict: verdict,
      modules_snapshot: []
    )
    lead
  end
end
