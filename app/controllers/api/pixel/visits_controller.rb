module Api
  module Pixel
    class VisitsController < BaseController
      def create
        body = params.permit(:session_id, :pixel_id, :page_url, :referrer, :started_at, :user_agent)
        return render json: { error: "invalid_page_url" }, status: :unprocessable_entity unless valid_page_url?(body[:page_url])
        return head :forbidden unless @pixel.permits_origin?(body[:page_url])

        capture = CaptureSession.find_or_create_by!(session_id: body[:session_id]) do |record|
          record.assign_attributes(
            pixel: @pixel, page_url: body[:page_url], referrer: body[:referrer],
            visitor_ip: request.remote_ip, user_agent: body[:user_agent],
            started_at: Time.zone.parse(body[:started_at].to_s) || Time.current,
            metadata: { "page_url" => body[:page_url] }
          )
        end
        return render json: { error: "session_conflict" }, status: :conflict if capture.pixel_id != @pixel.id

        render json: { session_id: capture.session_id }, status: :accepted
      rescue ActiveRecord::RecordInvalid, ArgumentError
        render json: { error: "invalid_visit" }, status: :unprocessable_entity
      end
    end
  end
end
