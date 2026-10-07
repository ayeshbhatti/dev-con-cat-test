module Api
  module Pixel
    class InteractionsController < BaseController
      def create
        capture = @pixel.capture_sessions.find_by!(session_id: params[:session_id])
        event = params.require(:interaction).permit(:name, :action, :at).to_h
        return head :unprocessable_entity unless %w[focus blur change].include?(event["action"]) && event["name"].to_s.length <= 80
        return head :forbidden unless @pixel.permits_origin?(URI.parse(capture.page_url).origin)
        capture.with_lock do
          interactions = Array(capture.metadata["interactions"])
          interactions << event
          capture.update!(metadata: capture.metadata.merge("interactions" => interactions.last(200)))
        end
        head :accepted
      rescue ActiveRecord::RecordNotFound
        head :not_found
      end
    end
  end
end
