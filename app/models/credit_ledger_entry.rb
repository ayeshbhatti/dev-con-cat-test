class CreditLedgerEntry < ApplicationRecord
  belongs_to :account
  belongs_to :verification_run, optional: true
  validates :amount, numericality: { other_than: 0 }
  validates :idempotency_key, presence: true, uniqueness: true
end
