require "test_helper"

class PixelManagementAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @account = Account.create!(external_id: "manage-a", name: "Manage A", plan: "starter", status: "active", enabled_modules: ["anura"])
    @other_account = Account.create!(external_id: "manage-b", name: "Manage B", plan: "starter", status: "active")
    @private_pixel = @other_account.pixels.create!(name: "Private pixel B", allowed_hosts: ["localhost"])
  end

  test "member cannot list or create pixels" do
    sign_in("member")
    get "/admin/pixels"
    assert_response :forbidden
    assert_no_difference "Pixel.count" do
      post "/admin/pixels", params: { name: "Forbidden", allowed_hosts: "localhost" }
    end
    assert_response :forbidden
  end

  test "account admin cannot redirect pixel management into another account" do
    sign_in("account_admin")
    get "/admin/pixels", params: { account_id: @other_account.id }
    assert_response :success
    assert_no_match(/Private pixel B/, response.body)
    post "/admin/pixels", params: { account_id: @other_account.id, name: "Scoped new pixel", allowed_hosts: "localhost" }
    assert_response :redirect
    pixel = Pixel.find_by!(name: "Scoped new pixel")
    assert_equal @account.id, pixel.account_id
    assert_equal ["anura"], pixel.enabled_modules
  end

  test "super admin may create a pixel for a selected account" do
    sign_in("super_admin")
    post "/admin/pixels", params: { account_id: @other_account.id, name: "Platform created", allowed_hosts: "localhost" }
    assert_response :redirect
    assert_equal @other_account.id, Pixel.find_by!(name: "Platform created").account_id
  end

  test "pixel management requires sign in" do
    get "/admin/pixels"
    assert_redirected_to "/login"
  end

  private

  def sign_in(role)
    user = User.create!(email: "#{role}@management.example.test", name: role, role: role,
                        account: role == "super_admin" ? nil : @account, password: "strong-password")
    post "/login", params: { email: user.email, password: "strong-password" }
    assert_response :redirect
  end
end
