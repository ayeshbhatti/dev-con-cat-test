require "securerandom"
require "uri"

class Pixel < ApplicationRecord
  belongs_to :account
  has_many :capture_sessions, dependent: :destroy
  has_many :leads, dependent: :restrict_with_error

  validates :public_id, presence: true, uniqueness: true
  validates :name, presence: true
  validate :allowed_hosts_are_hosts
  before_validation :generate_public_id, on: :create

  def permits_origin?(origin)
    return false if origin.blank?
    host = URI.parse(origin).host
    allowed_hosts.any? { |allowed| allowed == host || (allowed.start_with?("*.") && host&.end_with?(allowed.delete_prefix("*"))) }
  rescue URI::InvalidURIError
    false
  end

  private

  def generate_public_id
    self.public_id ||= "px_#{SecureRandom.hex(8)}"
  end

  def allowed_hosts_are_hosts
    errors.add(:allowed_hosts, "must be a list of hostnames") unless allowed_hosts.is_a?(Array) && allowed_hosts.all? { |host| host.is_a?(String) && host.match?(/\A(?:\*\.)?[a-z0-9.-]+\z/i) }
  end
end
