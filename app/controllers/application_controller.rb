class ApplicationController < ActionController::Base
  helper_method :current_user

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def authenticate_user!
    redirect_to login_path, alert: "Please sign in." unless current_user
  end

  def require_account_admin!
    head :forbidden unless current_user&.super_admin? || current_user&.account_admin?
  end

  def accessible_leads
    return Lead.all if current_user&.super_admin?
    Lead.where(account_id: current_user&.account_id)
  end
end
