class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    if current_user.super_admin?
      @accounts = Account.order(:name)
      @selected_account = params[:account_id].to_s
      leads = Lead.all
      leads = leads.where(account_id: @selected_account) if @selected_account.present?
    else
      @account = current_user.account
      leads = @account.leads
    end

    @search = params[:q].to_s.strip[0, 200]
    @verdict = params[:verdict].to_s

    if @search.present?
      pattern = "%#{Lead.sanitize_sql_like(@search)}%"
      leads = leads.where(
        <<~SQL.squish,
          concat_ws(' ',
            leads.external_id,
            leads.fields->>'first_name',
            leads.fields->>'last_name',
            leads.fields->>'email',
            leads.fields->>'phone'
          ) ILIKE ?
        SQL
        pattern
      )
    end

    if %w[ACCEPT REVIEW REJECT].include?(@verdict)
      latest_verdict = <<~SQL.squish
        (SELECT verification_runs.verdict
         FROM verification_runs
         WHERE verification_runs.lead_id = leads.id
         ORDER BY verification_runs.created_at DESC, verification_runs.id DESC
         LIMIT 1)
      SQL
      leads = leads.where("#{latest_verdict} = ?", @verdict)
    else
      @verdict = ""
    end

    @result_count = leads.count
    @recent_leads = leads
      .includes(:account, verification_runs: :consent_certificate)
      .recent
      .limit(50)
  end
end
