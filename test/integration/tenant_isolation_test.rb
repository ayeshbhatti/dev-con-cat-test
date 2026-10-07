require "test_helper"

class TenantIsolationTest < ActionDispatch::IntegrationTest
  test "an account member sees only their own leads" do
    account_a = Account.create!(external_id: "acct-a", name: "Account A", plan: "starter", status: "active")
    account_b = Account.create!(external_id: "acct-b", name: "Private Account B", plan: "starter", status: "active")
    user = account_a.users.create!(email: "a@example.test", name: "Member A", role: "member", password: "strong-password")
    pixel_b = account_b.pixels.create!(name: "Pixel B", allowed_hosts: ["localhost"])
    account_b.leads.create!(pixel: pixel_b, external_id: "secret-lead-b", fields: { "first_name" => "Hidden" })

    post "/login", params: { email: user.email, password: "strong-password" }
    follow_redirect!

    assert_response :success
    assert_no_match(/Private Account B|secret-lead-b|Hidden/, response.body)
  end

  test "one account pixel cannot fetch another account lead activity" do
    account_a = Account.create!(external_id: "acct-a", name: "Account A", plan: "starter", status: "active")
    account_b = Account.create!(external_id: "acct-b", name: "Account B", plan: "starter", status: "active")
    pixel_a = account_a.pixels.create!(name: "Pixel A", allowed_hosts: ["localhost"])
    pixel_b = account_b.pixels.create!(name: "Pixel B", allowed_hosts: ["localhost"])
    account_b.leads.create!(pixel: pixel_b, external_id: "private-lead", fields: { "first_name" => "Hidden" })

    get "/api/pixel/leads/private-lead/activity", params: { pixel_id: pixel_a.public_id, token: "some-token" }
    assert_response :not_found
  end
end
