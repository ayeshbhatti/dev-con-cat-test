class VerificationRun < ApplicationRecord
  belongs_to :lead
  has_many :layer_results, dependent: :destroy
  has_one :consent_certificate, dependent: :restrict_with_error
  has_one :credit_ledger_entry, dependent: :restrict_with_error

  enum :state, {
    queued: "queued",
    processing: "processing",
    completed: "completed",
    blocked: "blocked",
    failed: "failed"
  }

  validates :verdict,
            inclusion: { in: %w[ACCEPT REVIEW REJECT] },
            allow_nil: true
end
