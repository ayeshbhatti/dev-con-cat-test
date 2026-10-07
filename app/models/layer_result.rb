class LayerResult < ApplicationRecord
  belongs_to :verification_run

  enum :state, { not_enabled: "not_enabled", not_applicable: "not_applicable", returned: "returned", unavailable: "unavailable" }
  validates :layer, presence: true, uniqueness: { scope: :verification_run_id }
end
