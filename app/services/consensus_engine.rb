class ConsensusEngine
  def initialize(results)
    @results = results
  end

  def call
    hard_stops = []
    score = 0
    reasons = []
    unavailable = false
    @results.each do |result|
      if result.unavailable?
        unavailable = true
        reasons << "#{result.layer} was unavailable; the lead needs review."
        next
      end
      next unless result.returned?
      d = result.detail
      case result.layer
      when "anura"
        hard_stops << "Anura reported invalid traffic" if d["result"] == "bad"
        score += 2 if d["result"] == "suspect"
      when "trustedform"
        consent_matches = d["status"] == "verified" && d["matches_phone"] && d["matches_email"] && d["matches_page"] && d["consent_language_present"]
        hard_stops << "Consent evidence is #{d['status']} or does not match the submitted lead and page" unless consent_matches
      when "blacklist_alliance"
        hard_stops << "Confirmed serial litigator match" if d["status"] == "litigator"
        score += 2 if d["status"] == "suspected"
      when "dnc"
        hard_stops << "Phone is on a Do-Not-Call list" if %w[dnc_listed internal_dnc].include?(d["dnc_status"])
        score += 1 if d["callback_window_open"] == false && !%w[dnc_listed internal_dnc].include?(d["dnc_status"])
      when "vpn_proxy"
        hard_stops << "Traffic came through Tor" if d["is_tor"]
        score += 2 if d["is_vpn"] || d["is_proxy"] || d["is_datacenter"] || d["risk"] == "high" || d["site_visit_ip_matches_submit_ip"] == false
      when "phone_validation"
        valid = d.fetch("providers", {}).values.count { |v| v["valid"] }
        total = d.fetch("providers", {}).size
        score += (valid * 2 < total ? 3 : 1) if total.positive? && valid < total
      when "email_validation"
        providers = d.fetch("providers", {}).values
        undeliverable = providers.count { |v| v["deliverable"] == false }
        score += 2 if undeliverable == providers.size && providers.any?
        score += 1 if undeliverable.positive? && undeliverable < providers.size
        score += 1 if providers.any? { |v| v["disposable"] || v["fraud_score"].to_i >= 75 }
      when "enrichment"
        sources = d.values.select { |v| v.is_a?(Hash) }
        score += 2 if sources.length > 1 && sources.map { |v| v["address"] }.uniq.length > 1
        score += 1 if sources.any? { |v| v["match_to_lead"] == false }
      when "duplicate_detection"
        hard_stops << "Exact duplicate already exists in this buyer CRM" if d["match"] == "exact"
        score += 1 if d["match"] == "possible"
      when "voice"
        hard_stops << "Reused or synthetic voice detected" if %w[human_reused_actor synthetic].include?(d["verdict"])
      end
    end

    consent_result = @results.find { |result| result.layer == "trustedform" }
    consent_unproven = !consent_result&.returned?
    reasons << "Consent verification did not return a result; the lead cannot be accepted." if consent_unproven
    hard_stops.each { |reason| reasons << reason }
    verdict = if hard_stops.any? || score >= 6
      "REJECT"
    elsif score >= 2 || unavailable || consent_unproven
      "REVIEW"
    else
      "ACCEPT"
    end
    reasons << (verdict == "ACCEPT" ? "Enabled checks returned no material risk signals." : "Risk score: #{score}.")
    { verdict: verdict, score: score, reasons: reasons.uniq }
  end
end
