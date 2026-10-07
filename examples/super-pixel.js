/*
 * Super Pixel — reference embed snippet (candidate-facing example)
 * ---------------------------------------------------------------
 * This is the equivalent of a TrustedForm-style header snippet. A buyer drops
 * ONE tag on their landing page / funnel and the pixel:
 *
 *   1. Boots a "capture session" the moment the page loads and records page
 *      context (URL, referrer, user-agent, a client-side timestamp, and a
 *      site-visit beacon your backend can later match against the submit IP).
 *   2. Watches the lead form as the visitor fills it in (focus / blur / change)
 *      and streams those interactions to your backend in real time.
 *   3. On submit, POSTs the captured lead to YOUR Rails ingestion endpoint,
 *      then subscribes to verification activity for that lead so the page can
 *      render each detection layer's result live.
 *
 * WHAT CANDIDATES MUST BUILD (this file is intentionally NOT the solution):
 *   - The ingestion endpoint (data-endpoint below) that accepts a lead + session.
 *   - The transport that streams verification activity back (poll, SSE, or
 *     WebSocket/ActionCable — your call; justify it in your README).
 *   - The pixel-management UI that generates a pixel_id, scopes it to an
 *     account, and produces this snippet for the buyer to copy/paste.
 *
 * Everything below runs with ZERO backend by falling back to a local
 * simulation so the example landing page is demoable out of the box. Replace
 * the simulation with real calls to your Rails app.
 *
 * Embed like this (note the async + data-* attributes):
 *   <script async src="/super-pixel.js"
 *           data-pixel-id="px_9f2a01"
 *           data-endpoint="https://your-rails-app.example/api/pixel"></script>
 */
(function () {
  "use strict";

  var script =
    document.currentScript ||
    (function () {
      var s = document.getElementsByTagName("script");
      return s[s.length - 1];
    })();

  var CONFIG = {
    pixelId: (script && script.getAttribute("data-pixel-id")) || "px_demo",
    // When data-endpoint is absent we run in SIMULATION mode (no network).
    endpoint: (script && script.getAttribute("data-endpoint")) || null,
    // Which layers the pixel advertises it will run. In the real product this
    // comes from the account's enabled_modules; here it's just for the demo.
    layers: [
      "vpn_proxy",
      "anura",
      "trustedform",
      "blacklist_alliance",
      "dnc",
      "phone_validation",
      "email_validation",
      "enrichment",
      "duplicate_detection",
      "voice",
      "consensus",
    ],
  };

  // --- tiny event bus so the host page can render activity ------------------
  var listeners = [];
  function emit(evt) {
    for (var i = 0; i < listeners.length; i++) {
      try {
        listeners[i](evt);
      } catch (e) {
        /* never let a page listener break the pixel */
      }
    }
  }

  function sessionId() {
    if (window.crypto && window.crypto.randomUUID) return "sess_" + window.crypto.randomUUID();
    return "sess_" + Date.now().toString(36) + "_" + Math.random().toString(36).slice(2, 12);
  }

  var SESSION = {
    session_id: sessionId(),
    pixel_id: CONFIG.pixelId,
    page_url: location.href,
    referrer: document.referrer || null,
    user_agent: navigator.userAgent,
    started_at: new Date().toISOString(),
    interactions: [],
  };

  function post(path, body) {
    if (!CONFIG.endpoint) return Promise.resolve(null); // simulation mode
    return fetch(CONFIG.endpoint.replace(/\/$/, "") + path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      keepalive: true,
    })
      .then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (body) {
        body.http_status = r.status;
        return body;
      });
      })
      .catch(function () {
        return null;
      });
  }

  // Fire a site-visit beacon on load. Your backend records the visit IP here so
  // it can later be compared to the submit IP (the "VPN problem").
  var visitPromise = post("/visit", {
    session_id: SESSION.session_id,
    pixel_id: SESSION.pixel_id,
    page_url: SESSION.page_url,
    referrer: SESSION.referrer,
    started_at: SESSION.started_at,
    user_agent: SESSION.user_agent,
  });
  emit({ type: "session_started", session: SESSION });

  // --- form instrumentation -------------------------------------------------
  function trackForm(form) {
    var fields = form.querySelectorAll("input, select, textarea");
    Array.prototype.forEach.call(fields, function (el) {
      ["focus", "blur", "change"].forEach(function (type) {
        el.addEventListener(type, function () {
          var interaction = {
            name: el.name || el.id || "(unnamed)",
            action: type,
            at: new Date().toISOString(),
          };
          SESSION.interactions.push(interaction);
          emit({ type: "field", interaction: interaction });
          visitPromise.then(function () {
            post("/interactions", { session_id: SESSION.session_id, pixel_id: SESSION.pixel_id, interaction: interaction });
          });
        });
      });
    });

    form.addEventListener("submit", function (e) {
      // Prevent the demo page from navigating away; a real integration lets the
      // form submit normally and captures in parallel.
      if (form.hasAttribute("data-pixel-demo")) e.preventDefault();

      var data = {};
      Array.prototype.forEach.call(fields, function (el) {
        if (!el.name) return;
        if (el.type === "checkbox") data[el.name] = !!el.checked;
        else data[el.name] = el.value;
      });

      var lead = {
        session_id: SESSION.session_id,
        pixel_id: SESSION.pixel_id,
        submitted_at: new Date().toISOString(),
        form_dwell_ms:
          Date.now() - new Date(SESSION.interactions[0] ? SESSION.interactions[0].at : SESSION.started_at).getTime(),
        fields: data,
      };
      emit({ type: "submitted", lead: lead });

      // Real mode: hand the lead to your Rails app and stream results back.
      // Simulation mode: fake the layer-by-layer verification so the demo works.
      if (CONFIG.endpoint) {
        visitPromise.then(function () { return post("/leads", lead); }).then(function (res) {
          if (res && res.lead_id && res.activity_token) subscribeToActivity(res.lead_id, res.activity_token);
          else emit({ type: "info", message: res && res.error ? res.error : "Could not submit the lead." });
        });
      } else {
        simulateVerification(lead);
      }
    });
  }

  // Real transport is the candidate's job. This is the shape the page expects:
  //   { type: "layer_result", layer, verdict, detail }
  //   { type: "final_verdict", verdict, score, reasons }
  function subscribeToActivity(leadId, token) {
    emit({ type: "info", message: "Live verification started for " + leadId });
    var seen = {};
    var stopped = false;
    var url = CONFIG.endpoint.replace(/\/$/, "") + "/leads/" + encodeURIComponent(leadId) + "/activity?pixel_id=" + encodeURIComponent(CONFIG.pixelId);
    function poll() {
      if (stopped) return;
      fetch(url, { headers: { Accept: "application/json", Authorization: "Bearer " + token }, cache: "no-store" })
        .then(function (r) { if (!r.ok) throw new Error("activity unavailable"); return r.json(); })
        .then(function (data) {
          (data.events || []).forEach(function (evt) {
            if (seen[evt.id]) return;
            seen[evt.id] = true;
            emit(evt);
          });
          if (data.state === "completed" || data.state === "blocked" || data.state === "failed") stopped = true;
          else window.setTimeout(poll, 500);
        })
        .catch(function () {
          emit({ type: "info", message: "Live activity connection interrupted; retrying…" });
          window.setTimeout(poll, 1200);
        });
    }
    poll();
  }

  // ---- SIMULATION ONLY (delete once your backend is wired) -----------------
  function simulateVerification(lead) {
    var demo = {
      vpn_proxy: { verdict: "pass", detail: "residential IP, submit matches visit" },
      anura: { verdict: "pass", detail: "result: good" },
      trustedform: { verdict: "pass", detail: "cert verified, phone+email match" },
      blacklist_alliance: { verdict: "pass", detail: "no litigator match" },
      dnc: { verdict: "pass", detail: "callable, window open" },
      phone_validation: { verdict: "pass", detail: "3/3 providers valid mobile" },
      email_validation: { verdict: "pass", detail: "2/2 deliverable" },
      enrichment: { verdict: "pass", detail: "2 sources agree, identity matches" },
      duplicate_detection: { verdict: "pass", detail: "no CRM match for account" },
      voice: { verdict: "skip", detail: "no voice sample" },
    };
    var order = CONFIG.layers.filter(function (l) {
      return l !== "consensus";
    });
    var i = 0;
    (function step() {
      if (i >= order.length) {
        emit({
          type: "final_verdict",
          verdict: "ACCEPT",
          score: 0.94,
          reasons: ["all layers passed", "strong consensus"],
        });
        return;
      }
      var layer = order[i++];
      var r = demo[layer] || { verdict: "pass", detail: "" };
      emit({ type: "layer_result", layer: layer, verdict: r.verdict, detail: r.detail });
      setTimeout(step, 420 + Math.random() * 380);
    })();
  }

  // --- public API -----------------------------------------------------------
  window.SuperPixel = {
    config: CONFIG,
    session: SESSION,
    onActivity: function (fn) {
      listeners.push(fn);
    },
    attach: trackForm,
  };

  // Auto-attach to any form marked data-pixel-form once the DOM is ready.
  function boot() {
    var forms = document.querySelectorAll("form[data-pixel-form]");
    Array.prototype.forEach.call(forms, trackForm);
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
