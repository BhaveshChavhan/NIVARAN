"""
FastAPI ML Service
Exposes three endpoints that your existing backend can call:

  POST /predict/zone        → red zone risk for a location
  POST /verify/report       → is a report text credible?
  POST /score/trust         → reporter trust score
  POST /analyse/incident    → combined report + trust analysis
  POST /ingest/refresh      → trigger fresh data ingestion + zone update
  GET  /health              → health check
"""

from __future__ import annotations

import os
import logging
from contextlib import asynccontextmanager
from typing import Optional

import pandas as pd
import numpy as np
from fastapi import FastAPI, HTTPException, Header, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# ── Import our models ─────────────────────────────────────────────────────────
import sys
# Add the ml/ root to sys.path so sibling packages resolve
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from models.red_zone_predictor import RedZoneEnsemble
from models.report_verifier_trust_scorer import IncidentAnalyser
from data.ingestion_pipeline import DataIngestionPipeline, IngestionConfig

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

# ── Global model instances (loaded once at startup) ───────────────────────────
ensemble:  RedZoneEnsemble | None = None
analyser:  IncidentAnalyser | None = None
pipeline:  DataIngestionPipeline | None = None

API_KEY = os.getenv("ML_SERVICE_API_KEY", "changeme")


@asynccontextmanager
async def lifespan(app: FastAPI):
    global ensemble, analyser, pipeline
    logger.info("Loading ML models…")

    ensemble = RedZoneEnsemble()
    try:
        ensemble.xgb_model.load()
        logger.info("XGBoost model loaded.")
    except Exception as e:
        logger.warning(f"XGBoost model not found ({e}). Train it first with /train.")

    analyser = IncidentAnalyser()
    try:
        analyser.load_all()
        logger.info("Report verifier + trust scorer loaded.")
    except Exception as e:
        logger.warning(f"Analyser models not found ({e}). Train first.")

    pipeline = DataIngestionPipeline(IngestionConfig())
    logger.info("ML service ready.")
    yield
    logger.info("Shutting down.")


app = FastAPI(
    title="Safety App — ML Service",
    version="1.0.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Auth ──────────────────────────────────────────────────────────────────────
def verify_key(x_api_key: str = Header(default="")):
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")


# ══════════════════════════════════════════════════════════════════════════════
# REQUEST / RESPONSE SCHEMAS
# ══════════════════════════════════════════════════════════════════════════════

class LocationInput(BaseModel):
    latitude:  float = Field(..., ge=-90,  le=90)
    longitude: float = Field(..., ge=-180, le=180)
    timestamp: Optional[str] = None

class ZonePredictRequest(BaseModel):
    locations: list[LocationInput]
    # Optional overrides (injected from your backend's enrichment)
    news_crime_count:           Optional[float] = 0
    news_violence_count:        Optional[float] = 0
    social_media_alert_count:   Optional[float] = 0
    social_media_sentiment_score: Optional[float] = 0.5
    gov_report_count:           Optional[float] = 0
    past_incident_count:        Optional[float] = 0
    population_density:         Optional[float] = 0.5
    weather_severity:           Optional[float] = 0.0
    time_of_day_hour:           Optional[int]   = 12
    day_of_week:                Optional[int]   = 0
    is_weekend:                 Optional[int]   = 0

class ZonePredictResponse(BaseModel):
    predictions: list[dict]

class ReportVerifyRequest(BaseModel):
    report_text: str = Field(..., min_length=5)

class TrustScoreRequest(BaseModel):
    account_age_days:         float = 0
    past_reports_total:       float = 0
    past_reports_verified:    float = 0
    past_reports_fake:        float = 0
    accuracy_ratio:           float = 0
    geo_consistency_score:    float = 0.5
    device_trust_score:       float = 0.5
    report_frequency_7d:      float = 0
    corroboration_score:      float = 0
    time_since_last_report_h: float = 24
    is_verified_user:         float = 0
    media_attached:           float = 0
    cross_platform_match:     float = 0

class IncidentAnalyseRequest(BaseModel):
    report_text:   str
    reporter_meta: TrustScoreRequest


# ══════════════════════════════════════════════════════════════════════════════
# ENDPOINTS
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/health")
def health():
    return {
        "status": "ok",
        "xgb_ready":   ensemble is not None and ensemble.xgb_model.is_trained,
        "bert_ready":  analyser is not None and analyser.verifier.use_bert,
        "trust_ready": analyser is not None and analyser.scorer.is_trained,
    }


@app.post("/predict/zone", response_model=ZonePredictResponse,
          dependencies=[Depends(verify_key)])
def predict_zone(req: ZonePredictRequest):
    """
    Predict risk level (green / orange / red) for one or more locations.
    Call this from your backend when:
      - A user opens the map
      - A new incident is reported near a zone
      - On a scheduled cron (e.g. every 30 min)
    """
    if ensemble is None or not ensemble.xgb_model.is_trained:
        raise HTTPException(503, "Zone predictor not ready. Train the model first.")

    from datetime import datetime, timezone
    rows = []
    for loc in req.locations:
        ts = datetime.now(timezone.utc)
        if loc.timestamp:
            try:
                ts = datetime.fromisoformat(loc.timestamp)
            except Exception:
                pass
        row = {
            "latitude":  loc.latitude,
            "longitude": loc.longitude,
            "news_crime_count":              req.news_crime_count,
            "news_violence_count":           req.news_violence_count,
            "social_media_alert_count":      req.social_media_alert_count,
            "social_media_sentiment_score":  req.social_media_sentiment_score,
            "gov_report_count":              req.gov_report_count,
            "past_incident_count":           req.past_incident_count,
            "population_density":            req.population_density,
            "weather_severity":              req.weather_severity,
            "time_of_day_hour":              ts.hour,
            "day_of_week":                   ts.weekday(),
            "is_weekend":                    int(ts.weekday() >= 5),
        }
        rows.append(row)

    df  = pd.DataFrame(rows)
    out = ensemble.predict_tabular(df)

    predictions = []
    for i, loc in enumerate(req.locations):
        predictions.append({
            "latitude":     loc.latitude,
            "longitude":    loc.longitude,
            "risk_label":   out["risk_labels"][i],
            "risk_score":   round(out["risk_scores"][i], 4),
            "probabilities": {
                "green":  round(out["probabilities"][i][0], 4),
                "orange": round(out["probabilities"][i][1], 4),
                "red":    round(out["probabilities"][i][2], 4),
            }
        })

    return ZonePredictResponse(predictions=predictions)


@app.post("/verify/report", dependencies=[Depends(verify_key)])
def verify_report(req: ReportVerifyRequest):
    """
    Check whether a user-submitted incident report text is credible.
    Call this immediately when a user submits a report.
    """
    if analyser is None:
        raise HTTPException(503, "Report verifier not ready.")
    result = analyser.verifier.verify(req.report_text)
    return result


@app.post("/score/trust", dependencies=[Depends(verify_key)])
def score_trust(req: TrustScoreRequest):
    """
    Score how trustworthy a reporter is based on their metadata.
    Call this alongside /verify/report for combined analysis.
    """
    if analyser is None or not analyser.scorer.is_trained:
        raise HTTPException(503, "Trust scorer not ready.")
    result = analyser.scorer.score(req.dict())
    return result


@app.post("/analyse/incident", dependencies=[Depends(verify_key)])
def analyse_incident(req: IncidentAnalyseRequest):
    """
    Combined endpoint: verify report text + score reporter trust.
    Returns a final verdict: CONFIRMED_CREDIBLE / NEEDS_REVIEW / FLAGGED_FAKE.

    Recommended: call this for every new report. Pass the result to your
    admin panel and blockchain ledger.
    """
    if analyser is None:
        raise HTTPException(503, "Analyser not ready.")
    result = analyser.analyse(req.report_text, req.reporter_meta.dict())
    return result


@app.post("/ingest/refresh", dependencies=[Depends(verify_key)])
async def refresh_data():
    """
    Trigger a fresh data ingestion cycle.
    Call on a cron schedule (e.g. every 30 minutes) from your backend.
    Returns aggregated stats per geo-cell ready to use for zone prediction.
    """
    if pipeline is None:
        raise HTTPException(503, "Ingestion pipeline not ready.")
    df = pipeline.run()
    if df.empty:
        return {"status": "no_data", "rows": 0}

    stats = {
        "rows_ingested":  len(df),
        "sources":        df["source"].value_counts().to_dict() if "source" in df else {},
        "geo_tagged":     int(df["latitude"].notna().sum()),
        "timestamp":      df["timestamp"].max().isoformat() if "timestamp" in df and not df["timestamp"].isna().all() else None,
    }
    return {"status": "ok", **stats}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("api.main:app", host="0.0.0.0", port=8000, reload=True)
