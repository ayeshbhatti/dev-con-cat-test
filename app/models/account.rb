class Account < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :pixels, dependent: :destroy
  has_many :leads, dependent: :restrict_with_error
  has_many :credit_ledger_entries, dependent: :restrict_with_error

  validates :name, :plan, :status, presence: true
  validates :credits_remaining, numericality: { greater_than_or_equal_to: 0 }

  def super_admin_warning?
    status == "past_due" || (avg_daily_burn.to_i.positive? && credits_remaining < avg_daily_burn.to_i)
  end
end
