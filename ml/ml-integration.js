/**
 * ml-integration.js
 * Drop this into your existing Node.js / Express backend.
 * It wraps all ML service calls + LLM explain calls into clean async functions.
 *
 * Usage:
 *   const ml = require("./ml-integration");
 *   const result = await ml.analyseNewReport(reportText, reporterMeta);
 */

const axios = require("axios");

// ── Config ──────────────────────────────────────────────────────────────────
const ML_BASE_URL = process.env.ML_SERVICE_URL || "http://localhost:8000";
const ML_API_KEY  = process.env.ML_SERVICE_API_KEY || "changeme";
const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY || "";

const mlClient = axios.create({
  baseURL: ML_BASE_URL,
  headers: { "x-api-key": ML_API_KEY, "Content-Type": "application/json" },
  timeout: 15000,
});

const anthropicClient = axios.create({
  baseURL: "https://api.anthropic.com/v1",
  headers: {
    "x-api-key": ANTHROPIC_API_KEY,
    "anthropic-version": "2023-06-01",
    "Content-Type": "application/json",
  },
  timeout: 30000,
});


// ══════════════════════════════════════════════════════════════════════════════
// 1. ZONE PREDICTION
// ══════════════════════════════════════════════════════════════════════════════

/**
 * Predict risk zones for a list of locations.
 * Call this when a user opens the map or when you need to refresh zone colours.
 *
 * @param {Array<{latitude, longitude}>} locations
 * @param {Object} enrichmentData  — optional signal overrides from your backend
 * @returns {Array<{latitude, longitude, risk_label, risk_score, probabilities}>}
 */
async function predictZones(locations, enrichmentData = {}) {
  const payload = { locations, ...enrichmentData };
  const { data } = await mlClient.post("/predict/zone", payload);
  return data.predictions;
}

/**
 * Get zone prediction + LLM explanation for admin panel.
 */
async function predictZoneWithExplanation(location, enrichmentData = {}) {
  const predictions = await predictZones([location], enrichmentData);
  const prediction  = predictions[0];

  // Ask LLM to explain the prediction
  const explanation = await explainZone({ ...location, ...enrichmentData }, prediction);
  return { ...prediction, explanation };
}


// ══════════════════════════════════════════════════════════════════════════════
// 2. REPORT ANALYSIS
// ══════════════════════════════════════════════════════════════════════════════

/**
 * Analyse a new user-submitted report.
 * Returns ML verdict + LLM explanation + recommended action for admin panel.
 *
 * @param {string} reportText
 * @param {Object} reporterMeta  — see TrustScoreRequest schema in main.py
 * @returns {Object}
 */
async function analyseNewReport(reportText, reporterMeta) {
  const { data: mlResult } = await mlClient.post("/analyse/incident", {
    report_text:   reportText,
    reporter_meta: reporterMeta,
  });

  // LLM explanation for admin panel
  let explanation = null;
  if (ANTHROPIC_API_KEY) {
    explanation = await explainIncident(reportText, mlResult);
  }

  return {
    ...mlResult,
    llm_explanation: explanation,
    // Convenience field for your blockchain write
    should_store_on_chain: mlResult.final_verdict === "CONFIRMED_CREDIBLE",
    // Convenience field for push notifications
    should_alert_nearby_users: mlResult.final_verdict === "CONFIRMED_CREDIBLE",
  };
}

/**
 * Quick text-only check (no trust scoring). Use for pre-moderation.
 */
async function quickVerifyReport(reportText) {
  const { data } = await mlClient.post("/verify/report", { report_text: reportText });
  return data;
}


// ══════════════════════════════════════════════════════════════════════════════
// 3. LLM EXPLANATION HELPERS (using Anthropic Claude)
// ══════════════════════════════════════════════════════════════════════════════

async function callClaude(system, userMessage) {
  if (!ANTHROPIC_API_KEY) return null;
  try {
    const { data } = await anthropicClient.post("/messages", {
      model:      "claude-sonnet-4-20250514",
      max_tokens: 1024,
      system,
      messages: [{ role: "user", content: userMessage }],
    });
    const text = data.content?.find(b => b.type === "text")?.text || "";
    // Strip markdown code fences if any
    const clean = text.replace(/```json|```/g, "").trim();
    return JSON.parse(clean);
  } catch (err) {
    console.error("Claude API error:", err.message);
    return null;
  }
}

async function explainZone(zoneData, modelOutput) {
  const system = `You are a safety analyst. Given a zone risk prediction and its data signals,
return a JSON object with: summary, reasons (array), recommended_action, confidence_note.
Return ONLY valid JSON.`;

  const user = `
Zone: lat=${zoneData.latitude}, lon=${zoneData.longitude}
Risk label: ${modelOutput.risk_label}
Risk score: ${modelOutput.risk_score}
Signals:
  - News crime mentions: ${zoneData.news_crime_count || 0}
  - Social media alerts: ${zoneData.social_media_alert_count || 0}
  - Past incidents: ${zoneData.past_incident_count || 0}
  - Gov reports: ${zoneData.gov_report_count || 0}
Explain this zone's risk level and recommend an action.`;

  return callClaude(system, user);
}

async function explainIncident(reportText, mlResult) {
  const system = `You are a safety analyst reviewing incident reports.
Return a JSON with: verdict_explanation, linguistic_issues (array), 
what_makes_it_credible (array), admin_action (APPROVE|REVIEW|REJECT), action_reason.
Return ONLY valid JSON.`;

  const user = `
Report text: "${reportText.slice(0, 500)}"
ML verdict: ${mlResult.final_verdict}
Final score: ${mlResult.final_score}
Text verdict: ${mlResult.text_analysis?.verdict}
Trust score: ${mlResult.trust_analysis?.trust_score}
Explain and recommend an admin action.`;

  return callClaude(system, user);
}


// ══════════════════════════════════════════════════════════════════════════════
// 4. DATA REFRESH (cron job helper)
// ══════════════════════════════════════════════════════════════════════════════

/**
 * Trigger the ML service to pull fresh data from news/social/govt sources.
 * Call this on a cron schedule, e.g. every 30 minutes.
 */
async function refreshDataSources() {
  const { data } = await mlClient.post("/ingest/refresh");
  console.log("[ML] Data refresh result:", data);
  return data;
}


// ══════════════════════════════════════════════════════════════════════════════
// 5. EXPRESS ROUTE EXAMPLES (paste into your router)
// ══════════════════════════════════════════════════════════════════════════════

/**
 * Example Express routes — paste these into your routes/ml.js file.
 *
 * const express = require("express");
 * const router  = express.Router();
 * const ml      = require("../services/ml-integration");
 *
 * // Called by mobile app when map loads
 * router.post("/api/zones/predict", async (req, res) => {
 *   const { locations, ...enrichment } = req.body;
 *   const predictions = await ml.predictZones(locations, enrichment);
 *   res.json({ predictions });
 * });
 *
 * // Called when user submits a new incident report
 * router.post("/api/reports/submit", async (req, res) => {
 *   const { reportText, reporterMeta, latitude, longitude } = req.body;
 *   const analysis = await ml.analyseNewReport(reportText, reporterMeta);
 *
 *   if (analysis.should_store_on_chain) {
 *     // your existing blockchain write function:
 *     await blockchain.storeIncident({ reportText, latitude, longitude, ...analysis });
 *   }
 *
 *   if (analysis.should_alert_nearby_users) {
 *     // your push notification function:
 *     await notifications.alertNearby(latitude, longitude, analysis.final_verdict);
 *   }
 *
 *   res.json({ verdict: analysis.final_verdict, score: analysis.final_score });
 * });
 *
 * // Admin panel — get explanation for a specific zone
 * router.get("/api/admin/zone-explain", async (req, res) => {
 *   const { lat, lon } = req.query;
 *   const result = await ml.predictZoneWithExplanation({ latitude: +lat, longitude: +lon });
 *   res.json(result);
 * });
 */

module.exports = {
  predictZones,
  predictZoneWithExplanation,
  analyseNewReport,
  quickVerifyReport,
  refreshDataSources,
};
