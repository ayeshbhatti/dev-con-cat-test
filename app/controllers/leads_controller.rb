class LeadsController < ApplicationController
  before_action :authenticate_user!

  def show
    scope = current_user.super_admin? ? Lead.all : current_user.account.leads
    @lead = scope.includes(:account, :pixel, :capture_session).find(params[:id])
    @run = @lead.verification_runs.order(created_at: :desc, id: :desc).first
    @layers = @run ? @run.layer_results.order(:layer) : []
    @certificate = @run&.consent_certificate
    @capture = @lead.capture_session
    @interactions = Array(@capture&.metadata&.fetch("interactions", []))
      .select { |event| event.is_a?(Hash) }
      .sort_by { |event| event["at"].to_s }
    @events = @lead.activity_events
      .order(created_at: :desc, id: :desc).limit(200).to_a.reverse

    response.headers["Cache-Control"] = "no-store"
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
end
