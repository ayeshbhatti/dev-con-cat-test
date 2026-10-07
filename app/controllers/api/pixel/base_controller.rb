module Api
  module Pixel
    class BaseController < ActionController::API
      before_action :load_pixel
      before_action :check_origin

      private

      def load_pixel
        public_id = params[:pixel_id].presence || request.request_parameters.dig("pixel_id")
        @pixel = ::Pixel.find_by!(public_id: public_id, active: true)
      end

      def check_origin
        origin = request.headers["Origin"].presence || request.referer
        return if origin.blank? && !Rails.env.production?
        head :forbidden unless @pixel.permits_origin?(origin)
      end

      def valid_page_url?(value)
        uri = URI.parse(value.to_s)
        uri.is_a?(URI::HTTPS) || (Rails.env.development? && uri.is_a?(URI::HTTP))
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
