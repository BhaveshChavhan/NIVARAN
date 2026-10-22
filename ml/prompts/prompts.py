"""
prompts.py
LLM prompt templates used to enhance ML model outputs with natural-language reasoning.
These are called from your backend to give your admin panel human-readable explanations.

Usage:
    from prompts import PromptBuilder
    builder = PromptBuilder()
    prompt = builder.zone_analysis_prompt(zone_data, model_output)
    # then call Anthropic / OpenAI API with this prompt
"""

from typing import Any


class PromptBuilder:
    """
    Builds structured prompts for:
      1. Zone risk analysis — explain WHY a zone is red/orange/green
      2. Incident verification — explain WHY a report is credible/fake
      3. Trust assessment — explain WHY a reporter is trusted/flagged
      4. Data extraction from raw news text — NLP preprocessing helper
    """

    # ── SYSTEM PROMPT (shared) ────────────────────────────────────────────────
    SYSTEM_BASE = """You are an expert safety analyst for a community safety application.
Your role is to analyse data signals, explain risk predictions in clear language,
and help administrators make informed decisions about incidents and alerts.
Be precise, factual, and neutral. Never sensationalise. Avoid racial or demographic bias.
Always base your analysis on the data provided — do not hallucinate facts."""


    # ════════════════════════════════════════════════════════════════════════
    # PROMPT 1 — Zone risk explainer
    # ════════════════════════════════════════════════════════════════════════
    ZONE_ANALYSIS_SYSTEM = SYSTEM_BASE + """
You will receive:
  - A geographic zone's ML-predicted risk score and label
  - The data signals (news counts, social media counts, past incidents, etc.)
  - The top contributing features from the model

Your output must be a JSON object with these exact keys:
{
  "summary": "<1-2 sentence plain-language summary of the risk level>",
  "reasons": ["<reason 1>", "<reason 2>", "<reason 3>"],
  "recommended_action": "<what users or admins should do>",
  "confidence_note": "<any caveats about data quality or recency>"
}
Return ONLY the JSON object. No markdown, no preamble."""

    def zone_analysis_prompt(self, zone_data: dict, model_output: dict) -> dict:
        """
        zone_data:    dict with lat, lon, location_name, and raw feature values
        model_output: dict returned by RedZoneEnsemble.predict_tabular()
        """
        user_msg = f"""
Zone: {zone_data.get("location_name", f"{zone_data.get('latitude')}, {zone_data.get('longitude')}")}
Risk label: {model_output["risk_labels"][0]}
Risk score: {model_output["risk_scores"][0]:.3f}  (0=safe, 1=very dangerous)
Probability breakdown: green={model_output["probabilities"][0][0]:.2f}, orange={model_output["probabilities"][0][1]:.2f}, red={model_output["probabilities"][0][2]:.2f}

Data signals:
  - News crime mentions (last 24h): {zone_data.get("news_crime_count", 0)}
  - News violence mentions (last 24h): {zone_data.get("news_violence_count", 0)}
  - Social media alerts (last 6h): {zone_data.get("social_media_alert_count", 0)}
  - Social media sentiment score: {zone_data.get("social_media_sentiment_score", 0.5):.2f}  (0=very negative, 1=very positive)
  - Government reports (last 7 days): {zone_data.get("gov_report_count", 0)}
  - Confirmed past incidents (last 30 days): {zone_data.get("past_incident_count", 0)}
  - Population density index: {zone_data.get("population_density", 0.5):.2f}
  - Weather severity: {zone_data.get("weather_severity", 0):.2f}
  - Time of analysis: {zone_data.get("time_label", "daytime")}

Explain why this zone has been assigned the above risk level and what action is recommended.
"""
        return {"system": self.ZONE_ANALYSIS_SYSTEM, "user": user_msg}


    # ════════════════════════════════════════════════════════════════════════
    # PROMPT 2 — Report credibility explainer
    # ════════════════════════════════════════════════════════════════════════
    REPORT_VERIFY_SYSTEM = SYSTEM_BASE + """
You will receive:
  - A user-submitted incident report text
  - The ML model's credibility verdict (credible / suspicious / fake)
  - Spam flags and confidence scores

Your output must be a JSON object:
{
  "verdict_explanation": "<1-2 sentences explaining WHY the model gave this verdict>",
  "linguistic_issues": ["<any suspicious patterns found in text>"],
  "what_makes_it_credible": ["<if credible: specific details that support authenticity>"],
  "admin_action": "<APPROVE | REVIEW | REJECT>",
  "action_reason": "<one sentence>"
}
Return ONLY the JSON. No markdown."""

    def report_verify_prompt(self, report_text: str, model_output: dict) -> dict:
        flags_text = ""
        if model_output.get("spam_flags"):
            flag_names = ["URLs in text", "repeated chars", "all-caps text", "spam keywords", "profanity"]
            active = [flag_names[i] for i, f in enumerate(model_output["spam_flags"]) if f]
            flags_text = ", ".join(active) if active else "none"
        else:
            flags_text = "not analysed"

        user_msg = f"""
Report text submitted by user:
\"\"\"
{report_text[:1000]}
\"\"\"

ML model verdict: {model_output.get("verdict", "unknown")}
Confidence: {model_output.get("confidence", 0):.2f}
Scores: credible={model_output.get("scores", {}).get("credible", 0):.2f}, suspicious={model_output.get("scores", {}).get("suspicious", 0):.2f}, fake={model_output.get("scores", {}).get("fake", 0):.2f}
Spam score: {model_output.get("spam_score", 0):.2f}
Spam flags triggered: {flags_text}

Explain this verdict and recommend an admin action.
"""
        return {"system": self.REPORT_VERIFY_SYSTEM, "user": user_msg}


    # ════════════════════════════════════════════════════════════════════════
    # PROMPT 3 — Reporter trust explainer
    # ════════════════════════════════════════════════════════════════════════
    TRUST_EXPLAIN_SYSTEM = SYSTEM_BASE + """
You will receive metadata about a reporter and the ML trust model's output.

Your output must be a JSON object:
{
  "trust_summary": "<1-2 sentences about this reporter's trustworthiness>",
  "positive_signals": ["<factors that increase trust>"],
  "negative_signals": ["<factors that decrease trust>"],
  "recommendation": "<TRUST | MONITOR | BLOCK>",
  "recommendation_reason": "<one sentence>"
}
Return ONLY the JSON. No markdown."""

    def trust_explain_prompt(self, reporter_meta: dict, model_output: dict) -> dict:
        user_msg = f"""
Reporter metadata:
  - Account age: {reporter_meta.get("account_age_days", 0):.0f} days
  - Total reports submitted: {reporter_meta.get("past_reports_total", 0)}
  - Verified accurate reports: {reporter_meta.get("past_reports_verified", 0)}
  - Confirmed fake reports: {reporter_meta.get("past_reports_fake", 0)}
  - Accuracy ratio: {reporter_meta.get("accuracy_ratio", 0):.2f}
  - Geo-consistency (reports match usual location): {reporter_meta.get("geo_consistency_score", 0.5):.2f}
  - Device trust score: {reporter_meta.get("device_trust_score", 0.5):.2f}
  - Reports in last 7 days: {reporter_meta.get("report_frequency_7d", 0)}
  - Hours since last report: {reporter_meta.get("time_since_last_report_h", 24):.1f}
  - Phone/KYC verified: {"Yes" if reporter_meta.get("is_verified_user") else "No"}
  - Media (photo/video) attached: {"Yes" if reporter_meta.get("media_attached") else "No"}
  - Cross-platform corroboration: {reporter_meta.get("cross_platform_match", 0):.2f}

ML model output:
  Trust score: {model_output.get("trust_score", 0):.3f}  (0=untrustworthy, 1=fully trusted)
  Label: {model_output.get("label", "unknown")}
  Top factors: {", ".join(model_output.get("top_factors", []))}

Explain this trust assessment and recommend an action for the admin.
"""
        return {"system": self.TRUST_EXPLAIN_SYSTEM, "user": user_msg}


    # ════════════════════════════════════════════════════════════════════════
    # PROMPT 4 — Extract structured data from raw news/social text
    # ════════════════════════════════════════════════════════════════════════
    EXTRACT_SYSTEM = """You are a data extraction assistant for a safety intelligence system.
Extract structured incident data from raw news/social media text.

Return ONLY a JSON object with these keys (use null for missing data):
{
  "incident_type": "<crime|accident|fire|flood|riot|explosion|medical|other>",
  "location_text": "<exact location mentioned in text>",
  "estimated_severity": "<low|medium|high|critical>",
  "casualties_mentioned": "<number or null>",
  "date_mentioned": "<ISO date or null>",
  "source_credibility": "<high|medium|low>",
  "keywords": ["<up to 5 relevant keywords>"],
  "is_actionable": true or false
}
Return ONLY the JSON. No markdown. No preamble."""

    def extract_from_text_prompt(self, raw_text: str, source: str = "unknown") -> dict:
        user_msg = f"""
Source type: {source}
Raw text:
\"\"\"
{raw_text[:2000]}
\"\"\"

Extract incident data from this text.
"""
        return {"system": self.EXTRACT_SYSTEM, "user": user_msg}


    # ════════════════════════════════════════════════════════════════════════
    # HELPER: format for Anthropic API call
    # ════════════════════════════════════════════════════════════════════════
    @staticmethod
    def to_anthropic_payload(prompt_dict: dict, model: str = "claude-sonnet-4-20250514") -> dict:
        """
        Converts a prompt dict (system + user) into the Anthropic messages API payload.
        Pass this directly to requests.post("https://api.anthropic.com/v1/messages", json=payload)
        """
        return {
            "model": model,
            "max_tokens": 1024,
            "system": prompt_dict["system"],
            "messages": [
                {"role": "user", "content": prompt_dict["user"]}
            ]
        }

    @staticmethod
    def to_openai_payload(prompt_dict: dict, model: str = "gpt-4o-mini") -> dict:
        """For OpenAI-compatible APIs."""
        return {
            "model": model,
            "messages": [
                {"role": "system", "content": prompt_dict["system"]},
                {"role": "user",   "content": prompt_dict["user"]}
            ],
            "response_format": {"type": "json_object"}
        }
