class PixelAssetsController < ActionController::Base
  skip_forgery_protection only: :show

  def show
    response.headers["Cache-Control"] = "public, max-age=300"

    send_file Rails.root.join("examples/super-pixel.js"),
              type: "application/javascript",
              disposition: "inline"
  end
end