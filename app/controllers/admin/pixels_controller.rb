module Admin
  class PixelsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_account_admin!

    def index
      @account = current_user.super_admin? ? Account.find(params[:account_id]) : current_user.account
      @pixels = @account.pixels.order(:created_at)
    end

    def create
      @account = current_user.super_admin? ? Account.find(params[:account_id]) : current_user.account
      @pixel = @account.pixels.create!(name: params.require(:name), allowed_hosts: params[:allowed_hosts].to_s.split(/[\s,]+/).reject(&:blank?), enabled_modules: @account.enabled_modules)
      redirect_to admin_pixels_path(account_id: current_user.super_admin? ? @account.id : nil), notice: "Pixel created. Copy the snippet below."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_pixels_path(account_id: current_user.super_admin? ? @account&.id : nil), alert: e.record.errors.full_messages.to_sentence
    end
  end
end
