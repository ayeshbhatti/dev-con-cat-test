require "test_helper"

class DuplicateDetectorTest < ActiveSupport::TestCase
  setup do
    @account = create_account("Duplicate Account")
    @other_account = create_account("Other Duplicate Account")
  end

  test "normalizes phone and email when matching a previous lead" do
    previous = create_lead(@account, "(310) 555-0142", "MARIA@example.test")
    current = create_lead(@account, "3105550142", " maria@example.test ")

    outcome = DuplicateDetector.new(current).call

    assert_equal "exact", outcome[:detail]["match"]
    assert_equal "fail", outcome[:verdict]
    assert_equal previous.external_id, outcome[:detail]["crm_id"]
    assert_equal "platform", outcome[:detail]["source"]
  end

  test "does not match another account lead" do
    create_lead(@other_account, "3105550142", "maria@example.test")
    current = create_lead(@account, "3105550142", "maria@example.test")

    assert_equal "none", DuplicateDetector.new(current).call[:detail]["match"]
  end

  test "does not match itself or a later submission" do
    current = create_lead(@account, "3105550142", "maria@example.test")
    create_lead(@account, "3105550142", "maria@example.test")

    assert_equal "none", DuplicateDetector.new(current).call[:detail]["match"]
  end

  test "recent phone match with another email is a possible duplicate" do
    create_lead(@account, "3105550142", "earlier@example.test")
    current = create_lead(@account, "3105550142", "maria@example.test")

    outcome = DuplicateDetector.new(current).call

    assert_equal "possible", outcome[:detail]["match"]
    assert_equal "warn", outcome[:verdict]
  end

  test "phone-only match outside ninety days is not a possible duplicate" do
    previous = create_lead(@account, "3105550142", "earlier@example.test")
    previous.update!(created_at: 91.days.ago)
    current = create_lead(@account, "3105550142", "maria@example.test")

    assert_equal "none", DuplicateDetector.new(current).call[:detail]["match"]
  end

  test "supplied CRM fixtures still detect exact duplicates" do
    current = create_lead(@account, "3105550142", "maria@example.test")
    records = [{
      "crm_id" => "fixture-123",
      "phone" => "(310) 555-0142",
      "email" => "MARIA@example.test"
    }]

    outcome = DuplicateDetector.new(current, crm_records: records).call

    assert_equal "exact", outcome[:detail]["match"]
    assert_equal "fixture-123", outcome[:detail]["crm_id"]
    assert_equal "crm_fixture", outcome[:detail]["source"]
  end

  test "verification rejects an exact duplicate saved in the same account" do
    create_lead(@account, "3105550142", "maria@example.test")
    current = create_lead(@account, "3105550142", "maria@example.test")
    run = current.verification_runs.create!(
      state: "queued", modules_snapshot: ["duplicate_detection"]
    )

    VerificationJob.perform_now(run.id)

    assert_equal "completed", run.reload.state
    assert_equal "REJECT", run.verdict
    assert_match(/Exact duplicate/, run.reasons.join(" "))
    assert run.consent_certificate.valid_evidence?
  end

  private

  def create_account(name)
    Account.create!(
      external_id: "dup-#{SecureRandom.hex(6)}",
      name: name, plan: "starter", status: "active"
    )
  end

  def create_lead(account, phone, email)
    pixel = account.pixels.create!(
      name: "Duplicate Pixel", allowed_hosts: ["localhost"]
    )
    account.leads.create!(
      pixel: pixel,
      external_id: "dup-lead-#{SecureRandom.hex(6)}",
      fields: { "phone" => phone, "email" => email, "consent" => true }
    )
  end
end
