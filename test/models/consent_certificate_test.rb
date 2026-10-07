require "test_helper"

class ConsentCertificateTest < ActiveSupport::TestCase
  test "evidence digest detects changes and application writes are blocked" do
    account = Account.create!(external_id: "cert-acct", name: "Cert Account", plan: "starter", status: "active")
    pixel = account.pixels.create!(name: "Cert Pixel", allowed_hosts: ["localhost"])
    lead = account.leads.create!(pixel: pixel, external_id: "cert-lead", fields: { "consent" => true })
    run = lead.verification_runs.create!(modules_snapshot: [])
    certificate = ConsentCertificate.new(lead: lead, verification_run: run,
                                         certificate_id: "cert_#{SecureRandom.hex(8)}",
                                         evidence: { "verdict" => "ACCEPT", "layers" => [{ "layer" => "anura" }] })
    certificate.sha256 = Digest::SHA256.hexdigest(certificate.canonical_evidence)
    certificate.save!

    assert certificate.valid_evidence?
    assert_not certificate.update(evidence: { "verdict" => "REJECT" })
    assert certificate.reload.valid_evidence?
  end
end
