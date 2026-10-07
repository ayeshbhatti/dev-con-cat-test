require "test_helper"

class PublicCertificateTest < ActionDispatch::IntegrationTest
  test "public verification exposes integrity without submitted contact evidence" do
    account = Account.create!(external_id: "public-cert", name: "Public Cert", plan: "starter", status: "active")
    pixel = account.pixels.create!(name: "Public Cert Pixel", allowed_hosts: ["localhost"])
    lead = account.leads.create!(pixel: pixel, external_id: "public-cert-lead", fields: { "email" => "private-contact@example.test" })
    run = lead.verification_runs.create!(modules_snapshot: [])
    certificate = ConsentCertificate.new(lead: lead, verification_run: run, certificate_id: "cert_#{SecureRandom.hex(16)}",
                                          evidence: { "submitted_fields" => lead.fields, "verdict" => { "verdict" => "ACCEPT", "reasons" => [] } })
    certificate.sha256 = Digest::SHA256.hexdigest(certificate.canonical_evidence)
    certificate.save!

    get "/certificates/#{certificate.certificate_id}/verify"

    assert_response :success
    assert_equal true, response.parsed_body["valid"]
    assert_equal "ACCEPT", response.parsed_body.dig("verdict", "verdict")
    assert_no_match(/private-contact@example.test/, response.body)
  end
end
