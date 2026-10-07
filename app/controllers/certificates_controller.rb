class CertificatesController < ApplicationController
  def verify
    cert = ConsentCertificate.find_by!(certificate_id: params[:id])
    render json: { certificate_id: cert.certificate_id, valid: cert.valid_evidence?, sha256: cert.sha256, issued_at: cert.created_at, verdict: cert.evidence.dig("verdict") }
  end
end
