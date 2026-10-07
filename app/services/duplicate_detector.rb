class DuplicateDetector
  def initialize(lead, crm_records: [], fixture_time: nil)
    @lead = lead
    @crm_records = crm_records
    @fixture_time = fixture_time
  end

  def call
    phone = normalize_phone(@lead.fields["phone"])
    email = normalize_email(@lead.fields["email"])

    return result("none") if phone.blank? || email.blank?

    fixture_exact = @crm_records.find do |row|
      normalize_phone(row["phone"]) == phone &&
        normalize_email(row["email"]) == email
    end

    if fixture_exact
      return result("exact", source: "crm_fixture", crm_id: fixture_exact["crm_id"])
    end

    previous = @lead.account.leads
      .where("leads.id < ?", @lead.id)
      .where(
        "regexp_replace(COALESCE(leads.fields->>'phone', ''), '[^0-9]', '', 'g') = ?",
        phone
      )

    local_exact = previous.where(
      "LOWER(BTRIM(COALESCE(leads.fields->>'email', ''))) = ?",
      email
    ).order(id: :desc).first

    if local_exact
      return result("exact", source: "platform", crm_id: local_exact.external_id)
    end

    reference_time = parse_time(@fixture_time) || @lead.created_at
    fixture_possible = @crm_records.find do |row|
      captured_at = parse_time(row["created_at"])
      captured_at &&
        captured_at.between?(reference_time - 90.days, reference_time) &&
        normalize_phone(row["phone"]) == phone &&
        normalize_email(row["email"]) != email
    end

    if fixture_possible
      return result("possible", source: "crm_fixture", crm_id: fixture_possible["crm_id"])
    end

    local_possible = previous
      .where(created_at: (@lead.created_at - 90.days)..@lead.created_at)
      .where(
        "LOWER(BTRIM(COALESCE(leads.fields->>'email', ''))) <> ?",
        email
      ).order(id: :desc).first

    if local_possible
      return result("possible", source: "platform", crm_id: local_possible.external_id)
    end

    result("none")
  end

  private

  def result(match, source: nil, crm_id: nil)
    {
      state: "returned",
      verdict: { "exact" => "fail", "possible" => "warn", "none" => "pass" }.fetch(match),
      detail: { "match" => match, "source" => source, "crm_id" => crm_id }
    }
  end

  def normalize_phone(value)
    value.to_s.gsub(/\D/, "")
  end

  def normalize_email(value)
    value.to_s.downcase.strip
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
