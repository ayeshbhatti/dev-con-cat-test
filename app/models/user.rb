class User < ApplicationRecord
  has_secure_password
  belongs_to :account, optional: true

  enum :role, { super_admin: "super_admin", account_admin: "account_admin", member: "member" }
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validate :super_admin_has_no_account

  private

  def super_admin_has_no_account
    errors.add(:account, "must be blank for a super admin") if super_admin? && account_id.present?
    errors.add(:account, "is required for an account user") if !super_admin? && account_id.blank?
  end
end
