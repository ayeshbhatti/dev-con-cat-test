require "test_helper"

class ConsensusEngineTest < ActiveSupport::TestCase
  FakeResult = Struct.new(:layer, :state, :detail) do
    def returned? = state == "returned"
    def unavailable? = state == "unavailable"
  end

  test "accepts a clean set of returned results" do
    rows = [FakeResult.new("anura", "returned", { "result" => "good" }),
            FakeResult.new("trustedform", "returned", { "status" => "verified", "matches_phone" => true, "matches_email" => true,
                                                         "matches_page" => true, "consent_language_present" => true })]
    assert_equal "ACCEPT", ConsensusEngine.new(rows).call[:verdict]
  end

  test "confirmed hard stops reject regardless of other results" do
    rows = [FakeResult.new("blacklist_alliance", "returned", { "status" => "litigator" }),
            FakeResult.new("anura", "returned", { "result" => "good" })]
    outcome = ConsensusEngine.new(rows).call
    assert_equal "REJECT", outcome[:verdict]
    assert_match(/litigator/, outcome[:reasons].join(" "))
  end

  test "soft signals and unavailable checks lead to review rather than false acceptance" do
    rows = [FakeResult.new("anura", "returned", { "result" => "suspect" }),
            FakeResult.new("enrichment", "unavailable", {}),
            FakeResult.new("trustedform", "returned", { "status" => "verified", "matches_phone" => true, "matches_email" => true,
                                                         "matches_page" => true, "consent_language_present" => true })]
    assert_equal "REVIEW", ConsensusEngine.new(rows).call[:verdict]
  end
end
