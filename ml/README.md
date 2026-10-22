# Safety App — ML Module

Three ML models that plug into your existing backend + blockchain stack.

---

## What each model does

| Model | Algorithm | Input | Output |
|---|---|---|---|
| **1. Red Zone Predictor** | XGBoost + optional LSTM | Location + data signals (news, social, govt, past) | risk_label: green/orange/red + score |
| **2. Report Verifier** | BERT (+ rule-based fallback) | Incident report text | credible/suspicious/fake + confidence |
| **3. Trust Scorer** | Random Forest | Reporter metadata (history, device, geo) | trust_score 0-1 + label |

All three feed into a **Fusion Layer** that produces the final verdict shown on your map and admin panel.

---

## Project structure

```
ml/
├── models/
│   ├── red_zone_predictor.py          ← Model 1
│   └── report_verifier_trust_scorer.py ← Models 2 & 3
├── data/
│   └── ingestion_pipeline.py          ← fetches news/social/govt data
├── api/
│   └── main.py                        ← FastAPI service (3 REST endpoints)
├── prompts/
│   └── prompts.py                     ← LLM prompt templates
├── integration/
│   └── ml-integration.js              ← Drop into your Node.js backend
├── train_models.py                    ← Run once to train all models
├── requirements.txt
└── saved_models/                      ← created after training
```

---

## Setup

### 1. Install dependencies
```bash
cd ml
pip install -r requirements.txt
```

### 2. Set environment variables
```bash
# Copy to .env in your project root
ML_SERVICE_URL=http://localhost:8000
ML_SERVICE_API_KEY=your-secret-key
ANTHROPIC_API_KEY=your-anthropic-key      # optional, for LLM explanations
TWITTER_BEARER_TOKEN=your-twitter-token   # optional, for social media fetch
GNEWS_API_KEY=your-gnews-key              # optional, free tier at gnews.io
BACKEND_URL=http://localhost:3000         # your existing backend
BACKEND_API_KEY=your-backend-key
```

### 3. Train the models
```bash
# Will auto-generate synthetic data for smoke test if no real CSV exists
python train_models.py
```

For real training, put your labelled CSVs in `ml/data/`:
- `zone_training_data.csv` — with column `risk_label` (green/orange/red)
- `report_training_data.csv` — with column `label` (0=fake, 1=suspicious, 2=credible)
- `reporter_training_data.csv` — with column `is_trusted` (0 or 1)

### 4. Start the ML service
```bash
uvicorn ml.api.main:app --reload --port 8000
```

### 5. Add to your Node.js backend
```js
// In your package.json: "axios": "^1.6.0"
const ml = require("./services/ml-integration");
```

---

## API endpoints

All endpoints require header: `x-api-key: <your ML_SERVICE_API_KEY>`

### POST /predict/zone
```json
{
  "locations": [{"latitude": 19.076, "longitude": 72.877}],
  "news_crime_count": 3,
  "social_media_alert_count": 5,
  "past_incident_count": 2
}
```
Response:
```json
{
  "predictions": [{
    "latitude": 19.076,
    "longitude": 72.877,
    "risk_label": "red",
    "risk_score": 0.82,
    "probabilities": {"green": 0.05, "orange": 0.13, "red": 0.82}
  }]
}
```

### POST /analyse/incident
```json
{
  "report_text": "There was a robbery near the market at 10 PM...",
  "reporter_meta": {
    "account_age_days": 180,
    "past_reports_total": 12,
    "past_reports_verified": 9,
    "past_reports_fake": 1,
    "accuracy_ratio": 0.75,
    "is_verified_user": 1,
    "media_attached": 1,
    "geo_consistency_score": 0.9,
    "device_trust_score": 0.8,
    "cross_platform_match": 0.6,
    "report_frequency_7d": 2,
    "time_since_last_report_h": 48,
    "corroboration_score": 0.7
  }
}
```
Response:
```json
{
  "final_verdict": "CONFIRMED_CREDIBLE",
  "final_score": 0.78,
  "text_analysis": {"verdict": "credible", "confidence": 0.82, ...},
  "trust_analysis": {"trust_score": 0.73, "label": "trusted", ...}
}
```

### POST /ingest/refresh
Triggers fresh data pull from all configured sources. Call on cron every 30 min.

### GET /health
Returns readiness status of all three models.

---

## How to wire into your existing blockchain flow

```js
// In your report submission handler:
const analysis = await ml.analyseNewReport(reportText, reporterMeta);

if (analysis.final_verdict === "CONFIRMED_CREDIBLE") {
  // Write to blockchain as verified incident
  await blockchain.storeIncident({
    description: reportText,
    latitude, longitude,
    verified: true,
    ml_score: analysis.final_score,
    timestamp: new Date().toISOString()
  });
  // Notify nearby users
  await pushNotifications.alertNearby(latitude, longitude, "red");
} else if (analysis.final_verdict === "NEEDS_REVIEW") {
  // Queue for admin review — do NOT write to chain yet
  await adminQueue.add({ reportText, analysis });
} else {
  // FLAGGED_FAKE — log silently, update reporter's fake count
  await userService.incrementFakeCount(reporterId);
}
```

---

## Scheduled cron jobs to add

```js
// In your cron scheduler (e.g. node-cron):
const cron = require("node-cron");
const ml   = require("./services/ml-integration");

// Refresh data sources every 30 minutes
cron.schedule("*/30 * * * *", () => ml.refreshDataSources());

// Refresh zone predictions every hour
cron.schedule("0 * * * *", async () => {
  const zones = await db.getAllMonitoredZones();
  const predictions = await ml.predictZones(zones);
  await db.updateZoneRiskLevels(predictions);
});
```

---

## To enable BERT-based report verification (better accuracy)

```bash
pip install transformers torch datasets
```

Then in `train_models.py`, change:
```python
train_report_verifier("data/report_training_data.csv", use_bert=True)
```

Requires GPU for fast fine-tuning, but CPU works (slower).
BERT is optional — the rule-based fallback works without it.

---

## Minimum training data targets

| Model | Minimum rows | Recommended |
|---|---|---|
| Zone predictor | 500 | 2000+ |
| Report verifier | 300/class | 1000/class |
| Trust scorer | 200 | 500+ |

Bootstrap with your blockchain's historical incidents as ground truth.
