require "digest"
require "json"

class ConsentCertificate < ApplicationRecord
  belongs_to :lead
  belongs_to :verification_run

  validates :certificate_id, presence: true, uniqueness: true
  validates :sha256, presence: true, uniqueness: true
  before_update { throw :abort }
  before_destroy { throw :abort }

  def valid_evidence?
    Digest::SHA256.hexdigest(canonical_evidence) == sha256
  end

  def canonical_evidence
    JSON.generate(stable(evidence.deep_stringify_keys))
  end

  private

  def stable(value)
    case value
    when Hash then value.keys.sort.to_h { |key| [key, stable(value[key])] }
    when Array then value.map { |item| stable(item) }
    else value
    end
  end
end
