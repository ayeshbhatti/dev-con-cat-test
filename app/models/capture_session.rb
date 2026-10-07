class CaptureSession < ApplicationRecord
  belongs_to :pixel
  has_one :lead, dependent: :nullify
  validates :session_id, presence: true, uniqueness: true
end
