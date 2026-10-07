require "digest"

class Lead < ApplicationRecord
  belongs_to :account
  belongs_to :pixel
  belongs_to :capture_session, optional: true
  has_many :verification_runs, dependent: :destroy
  has_many :activity_events, dependent: :destroy
  has_many :consent_certificates, dependent: :restrict_with_error

  validates :external_id, presence: true, uniqueness: { scope: :account_id }
  validates :fields, presence: true
  scope :recent, -> { order(created_at: :desc) }

  def current_run
    if verification_runs.loaded?
      verification_runs.max_by { |run| [run.created_at, run.id] }
    else
      verification_runs.order(created_at: :desc, id: :desc).first
    end
  end

  def activity_token_valid?(token)
    return false if token.blank? || activity_token_digest.blank?
    ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(token), activity_token_digest)
  end
end
