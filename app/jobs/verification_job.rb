require "digest"
require "securerandom"

class VerificationJob < ApplicationJob
  queue_as :default

  LAYERS = %w[vpn_proxy anura trustedform blacklist_alliance dnc phone_validation email_validation enrichment duplicate_detection voice].freeze

  def perform(run_id)
    claimed = false
    run = VerificationRun.includes(:lead).find(run_id)

    run.with_lock do
      if run.queued?
        run.update!(state: "processing", started_at: Time.current)
        claimed = true
      end
    end

    return unless claimed
    ActivityEvent.create!(lead: run.lead, event_type: "verification_started", payload: { "run_id" => run.id })
    lookup = MockFixtureLookup.new(run.lead)
    results = LAYERS.map { |layer| persist_layer(run, layer, lookup) }
    outcome = ConsensusEngine.new(results).call
    run.with_lock do
      certificate = issue_certificate(run, lookup, outcome)
      run.update!(state: "completed", verdict: outcome[:verdict], score: outcome[:score], reasons: outcome[:reasons], finished_at: Time.current)
      ActivityEvent.create!(lead: run.lead, event_type: "final_verdict", payload: outcome.merge("certificate_id" => certificate.certificate_id))
    end
  rescue StandardError => e
    if run && claimed
      run.reload
      run.update!(state: "failed", verdict: "REVIEW", reasons: ["Verification could not complete safely."], finished_at: Time.current)
      LAYERS.each do |layer|
        next if run.layer_results.exists?(layer: layer)
        state = run.modules_snapshot.include?(layer) ? "unavailable" : "not_enabled"
        result = run.layer_results.create!(layer: layer, state: state, verdict: state == "unavailable" ? "error" : "skip",
                                           detail: { "reason" => "Verification stopped before this layer completed." })
        ActivityEvent.create!(lead: run.lead, event_type: "layer_result",
                              payload: { "layer" => layer, "verdict" => result.verdict, "detail" => result.detail, "state" => result.state })
      end
      unless run.consent_certificate
        begin
          outcome = { verdict: "REVIEW", score: 0, reasons: run.reasons }
          certificate = issue_certificate(run, MockFixtureLookup.new(run.lead), outcome)
          ActivityEvent.create!(lead: run.lead, event_type: "final_verdict",
                                payload: outcome.merge("certificate_id" => certificate.certificate_id))
        rescue StandardError => certificate_error
          Rails.logger.error("Unable to issue failure certificate run=#{run_id} #{certificate_error.class}: #{certificate_error.message}")
        end
      end
    end
    Rails.logger.error("VerificationJob failed run=#{run_id} #{e.class}: #{e.message}")
    raise
  end

  private

  def persist_layer(run, layer, lookup)
    result = begin
      enabled = run.modules_snapshot.include?(layer)
      if !enabled
        { state: "not_enabled", verdict: "skip", detail: { "reason" => "Module is not enabled for this pixel." } }
      elsif layer == "duplicate_detection"
        duplicate_result(run.lead, lookup)
      else
        raw = lookup.provider(layer)
        if layer == "voice" && raw && raw["has_sample"] == false
          { state: "not_applicable", verdict: "skip", detail: raw.merge("reason" => "No voice sample was submitted.") }
        elsif raw.nil?
          { state: "unavailable", verdict: "error", detail: { "reason" => "No mock provider result matched this lead." } }
        else
          normalize_result(layer, raw, run.lead)
        end
      end
    rescue StandardError => e
      { state: "unavailable", verdict: "error", detail: { "reason" => "Provider fixture failed: #{e.class}" } }
    end

    LayerResult.transaction do
      row = run.layer_results.create!(layer: layer, state: result[:state], verdict: result[:verdict],
                                      detail: result[:detail], completed_at: Time.current)
      ActivityEvent.create!(lead: run.lead, event_type: "layer_result",
                            payload: { "layer" => layer, "verdict" => row.verdict,
                                       "detail" => activity_detail(layer, row), "state" => row.state })
      row
    end
  end

  def normalize_result(layer, raw, lead)
    raw = raw.merge("matches_page" => raw["page_url"].to_s == lead.landing_page_url.to_s) if layer == "trustedform"
    verdict = case layer
    when "vpn_proxy"
      raw["is_tor"] ? "fail" : (raw["is_vpn"] || raw["is_proxy"] || raw["is_datacenter"] || raw["site_visit_ip_matches_submit_ip"] == false ? "warn" : "pass")
    when "anura" then { "good" => "pass", "suspect" => "warn", "bad" => "fail" }.fetch(raw["result"], "error")
    when "trustedform" then raw["status"] == "verified" && raw["matches_phone"] && raw["matches_email"] && raw["matches_page"] && raw["consent_language_present"] ? "pass" : "fail"
    when "blacklist_alliance" then { "clean" => "pass", "suspected" => "warn", "litigator" => "fail" }.fetch(raw["status"], "error")
    when "dnc" then %w[dnc_listed internal_dnc].include?(raw["dnc_status"]) ? "fail" : "pass"
    when "phone_validation"
      providers = raw.fetch("providers", {}).values
      valid = providers.count { |provider| provider["valid"] }
      valid == providers.length && valid.positive? ? "pass" : "warn"
    when "email_validation"
      providers = raw.fetch("providers", {}).values
      providers.all? { |provider| provider["deliverable"] } && providers.none? { |provider| provider["disposable"] } ? "pass" : "warn"
    when "enrichment"
      sources = raw.values.select { |value| value.is_a?(Hash) }
      sources.length > 1 && sources.map { |value| value["address"] }.uniq.length == 1 && sources.all? { |value| value["match_to_lead"] } ? "pass" : "warn"
    when "voice" then %w[human_reused_actor synthetic].include?(raw["verdict"]) ? "fail" : "pass"
    else "error"
    end
    { state: "returned", verdict: verdict, detail: raw }
  end

  def duplicate_result(lead, lookup)
    DuplicateDetector.new(
      lead,
      crm_records: lookup.crm_records,
      fixture_time: lookup.lead_fixture&.fetch("captured_at", nil)
    ).call
  end

  def issue_certificate(run, lookup, outcome)
    capture = run.lead.capture_session
    capture_evidence = if capture
      {
        "session_id" => capture.session_id,
        "page_url" => capture.page_url,
        "referrer" => capture.referrer,
        "user_agent" => capture.user_agent,
        "started_at" => capture.started_at.iso8601(6),
        "interactions" => Array(capture.metadata["interactions"]),
        "interaction_timestamps_source" => "browser_reported"
      }
    end
    evidence = {
      "version" => 2,
      "capture_session" => capture_evidence,
      "lead_id" => run.lead.external_id,
      "account_id" => run.lead.account.external_id,
      "pixel_id" => run.lead.pixel.public_id,
      "captured_at" => run.lead.created_at.iso8601(6),
      "page_url" => run.lead.landing_page_url,
      "visitor_ip" => run.lead.capture_session&.visitor_ip,
      "submit_ip" => run.lead.submit_ip,
      "submitted_fields" => run.lead.fields,
      "trustedform_reference" => run.lead.fields["trusted_form_cert_url"] || lookup.lead_fixture&.fetch("trusted_form_cert_url", nil),
      "layers" => run.layer_results.order(:layer).map { |row| { "layer" => row.layer, "state" => row.state, "verdict" => row.verdict, "detail" => row.detail } },
      "verdict" => outcome,
      "issued_at" => Time.current.iso8601(6)
    }
    certificate = ConsentCertificate.new(lead: run.lead, verification_run: run, certificate_id: "cert_#{SecureRandom.hex(16)}", evidence: evidence)
    certificate.sha256 = Digest::SHA256.hexdigest(certificate.canonical_evidence)
    certificate.save!
    certificate
  end

  def activity_detail(layer, row)
    d = row.detail
    return d.slice("reason") unless row.returned?
    case layer
    when "anura" then { "result" => d["result"], "rule_count" => Array(d["rule_ids"]).size }
    when "trustedform" then d.slice("status", "matches_phone", "matches_email", "matches_page", "consent_language_present")
    when "blacklist_alliance" then d.slice("status")
    when "dnc" then d.slice("dnc_status", "callback_window_open")
    when "vpn_proxy" then d.slice("risk", "is_vpn", "is_proxy", "is_tor", "is_datacenter", "site_visit_ip_matches_submit_ip")
    when "phone_validation"
      values = d.fetch("providers", {}).values
      { "providers" => values.size, "valid" => values.count { |value| value["valid"] } }
    when "email_validation"
      values = d.fetch("providers", {}).values
      { "providers" => values.size, "deliverable" => values.count { |value| value["deliverable"] }, "disposable" => values.any? { |value| value["disposable"] } }
    when "enrichment"
      values = d.values.select { |value| value.is_a?(Hash) }
      { "sources" => values.size, "identity_matches" => values.count { |value| value["match_to_lead"] } }
    when "duplicate_detection" then d.slice("match")
    when "voice" then d.slice("verdict", "has_sample")
    else {}
    end
  end

  def normalize(value) = value.to_s.gsub(/\D/, "")
end
