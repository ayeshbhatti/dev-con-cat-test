require "test_helper"

class ConsensusAvailabilityTest < ActiveSupport::TestCase
  FakeResult = Struct.new(:layer, :state, :detail) do
    def returned? = state == "returned"
    def unavailable? = state == "unavailable"
  end

  test "unavailable consent requires review instead of rejection" do
    rows = [FakeResult.new("trustedform", "unavailable", {})]

    outcome = ConsensusEngine.new(rows).call

    assert_equal "REVIEW", outcome[:verdict]
    assert_equal 0, outcome[:score]
    assert outcome[:reasons].any? { |reason| reason.include?("unavailable") }
    refute outcome[:reasons].any? { |reason| reason.include?("no material risk signals") }
  end

  test "returned consent with a page mismatch is rejected" do
    rows = [
      FakeResult.new("trustedform", "returned", {
        "status" => "verified",
        "matches_phone" => true,
        "matches_email" => true,
        "matches_page" => false,
        "consent_language_present" => true
      })
    ]

    assert_equal "REJECT", ConsensusEngine.new(rows).call[:verdict]
  end

  test "confirmed fraud still rejects when consent is unavailable" do
    rows = [
      FakeResult.new("trustedform", "unavailable", {}),
      FakeResult.new("anura", "returned", { "result" => "bad" })
    ]

    assert_equal "REJECT", ConsensusEngine.new(rows).call[:verdict]
  end
end
