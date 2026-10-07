class MockFixtureLookup
  def initialize(lead)
    @lead = lead
    @datasets = ProviderDataset.pluck(:name, :data).to_h
  end

  def lead_key
    lead_fixture&.fetch("lead_id", nil)
  end

  def lead_fixture
    email = @lead.fields["email"].to_s.downcase.strip
    phone = normalize_phone(@lead.fields["phone"])
    Array(@datasets.dig("leads", "leads")).find do |record|
      record["email"].to_s.downcase == email && normalize_phone(record["phone"]) == phone
    end
  end

  def provider(name)
    key = lead_key
    return nil unless key
    data = @datasets.dig(name, "results")
    data.is_a?(Hash) ? data[key] : nil
  end

  def crm_records
    Array(@datasets.dig("buyers_crm", "crm_records", @lead.account.external_id))
  end

  private

  def normalize_phone(value) = value.to_s.gsub(/\D/, "")
end
