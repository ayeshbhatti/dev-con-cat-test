module Api
  module Pixel
    class LeadsController < BaseController
      def create
        body = params.permit(:session_id, :pixel_id, :submitted_at, :form_dwell_ms, fields: {})
        capture = @pixel.capture_sessions.find_by!(session_id: body[:session_id])
        return head :forbidden unless @pixel.permits_origin?(capture.page_url)
        return head :gone if capture.started_at < 24.hours.ago || capture.started_at > 5.minutes.from_now

        fields = body[:fields].to_h.slice("first_name", "last_name", "email", "phone", "consent")
        return render json: { error: "required_fields_missing" }, status: :unprocessable_entity if %w[first_name last_name email phone].any? { |key| fields[key].blank? }
        return render json: { error: "consent_required" }, status: :unprocessable_entity unless fields["consent"].to_s.in?(%w[true 1 on yes])

        lead, run, activity_token = LeadIntake.new(pixel: @pixel, capture_session: capture, fields: fields,
                                   submit_ip: request.remote_ip, user_agent: request.user_agent,
                                   dwell_ms: body[:form_dwell_ms]).call
        render json: { lead_id: lead.external_id, status: run.state,
                       activity_token: activity_token,
                       certificate_url: run.consent_certificate&.then { |c| "/certificates/#{c.certificate_id}/verify" } }, status: :created
      rescue ActiveRecord::RecordNotFound
        render json: { error: "unknown_session" }, status: :not_found
      rescue ActiveRecord::RecordNotUnique
        render json: { error: "duplicate_submission" }, status: :conflict
      end

      def activity
        lead = @pixel.account.leads.find_by!(external_id: params[:id])
        token = request.authorization.to_s.delete_prefix("Bearer ")
        return head :forbidden unless lead.activity_token_valid?(token)
        events = lead.activity_events.order(:id).map { |event| { id: event.id, type: event.event_type, created_at: event.created_at, **event.payload } }
        run = lead.current_run
        render json: { events: events, state: run&.state, verdict: run&.verdict, score: run&.score, reasons: run&.reasons,
                       certificate_id: run&.consent_certificate&.certificate_id }
      end
    end
  end
end
