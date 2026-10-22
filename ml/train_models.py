"""
train_models.py
Run this script ONCE to train all three models on your labelled data.
After training, the models are saved to ./saved_models/ and loaded
automatically when the FastAPI service starts.

Steps:
  1. Prepare labelled CSV files (see format below)
  2. pip install -r requirements.txt
  3. python train_models.py

─────────────────────────────────────────────────────
TRAINING DATA FORMAT
─────────────────────────────────────────────────────

zone_training_data.csv (for Model 1 — Red Zone Predictor):
  Required columns:
    latitude, longitude, timestamp,
    news_crime_count, news_violence_count,
    social_media_alert_count, social_media_sentiment_score,
    gov_report_count, past_incident_count,
    time_of_day_hour, day_of_week, is_weekend,
    population_density, weather_severity,
    risk_label   ← your label: "green", "orange", or "red"

  Minimum recommended: 500+ rows, balanced across labels.
  Tip: bootstrap from your blockchain DB past incidents as "red" zones
       and areas with no history as "green" zones.

report_training_data.csv (for Model 2 — Report Verifier):
  Required columns:
    text        ← the report text
    label       ← 0=fake, 1=suspicious, 2=credible

  Minimum recommended: 300+ rows per class.
  Tip: manually label 200 real reports from your app + generate 200 synthetic fakes.

reporter_training_data.csv (for Model 3 — Trust Scorer):
  Required columns: all TRUST_FEATURE_COLS plus is_trusted (0 or 1)
  Minimum recommended: 200+ rows.
  Tip: users whose reports were verified = 1, users who were banned = 0.
"""

import os
import sys
import pandas as pd

# Ensure ml/ root is on sys.path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from models.red_zone_predictor import RedZoneEnsemble
from models.report_verifier_trust_scorer import ReportVerifier, TrustScorer


def train_zone_model(csv_path: str):
    print("\n=== Training Model 1: Red Zone Predictor ===")
    df = pd.read_csv(csv_path)
    print(f"Loaded {len(df)} rows. Label distribution:\n{df['risk_label'].value_counts()}")
    ensemble = RedZoneEnsemble()
    ensemble.xgb_model.fit(df, label_col="risk_label")
    ensemble.xgb_model.save()
    print("Model 1 saved.")


def train_report_verifier(csv_path: str, use_bert=False):
    print("\n=== Training Model 2: Report Verifier ===")
    df = pd.read_csv(csv_path)
    print(f"Loaded {len(df)} rows. Label distribution:\n{df['label'].value_counts()}")

    verifier = ReportVerifier()
    if use_bert:
        verifier.fine_tune(
            texts=df["text"].tolist(),
            labels=df["label"].tolist(),
            epochs=3
        )
        print("BERT fine-tuning complete.")
    else:
        print("Skipping BERT fine-tuning (use_bert=False). Rule-based fallback will be used.")
        print("To enable BERT: pip install transformers torch && set use_bert=True")


def train_trust_scorer(csv_path: str):
    print("\n=== Training Model 3: Trust Scorer ===")
    df = pd.read_csv(csv_path)
    print(f"Loaded {len(df)} rows. Label distribution:\n{df['is_trusted'].value_counts()}")
    scorer = TrustScorer()
    scorer.fit(df, label_col="is_trusted")
    scorer.save()
    print("Model 3 saved.")


# ── Synthetic data generator (for quick testing without real data) ────────────
def generate_synthetic_data():
    """Generates small synthetic datasets for smoke-testing the pipeline."""
    import numpy as np
    print("\nGenerating synthetic training data for smoke test…")

    np.random.seed(42)
    n = 600

    # Zone data
    zone_df = pd.DataFrame({
        "latitude":  np.random.uniform(18.8, 19.3, n),
        "longitude": np.random.uniform(72.7, 73.1, n),
        "timestamp": pd.date_range("2024-01-01", periods=n, freq="1h"),
        "news_crime_count":              np.random.poisson(1, n),
        "news_violence_count":           np.random.poisson(0.5, n),
        "social_media_alert_count":      np.random.poisson(2, n),
        "social_media_sentiment_score":  np.random.beta(5, 2, n),
        "gov_report_count":              np.random.poisson(0.3, n),
        "past_incident_count":           np.random.poisson(1.5, n),
        "time_of_day_hour":              np.random.randint(0, 24, n),
        "day_of_week":                   np.random.randint(0, 7, n),
        "is_weekend":                    np.random.randint(0, 2, n),
        "population_density":            np.random.uniform(0.1, 1.0, n),
        "weather_severity":              np.random.uniform(0, 0.5, n),
    })
    crime = zone_df["news_crime_count"] + zone_df["news_violence_count"] + zone_df["past_incident_count"]
    zone_df["risk_label"] = pd.cut(crime, bins=[-1, 1, 3, 100], labels=["green", "orange", "red"])
    zone_df.to_csv("data/zone_training_data.csv", index=False)
    print("  zone_training_data.csv written.")

    # Report data
    fake_reports = ["click here to win prize http://spam.com", "BUY NOW!!!! CHEAP!!!", "test test test"] * 40
    real_reports = [
        "There was a robbery near the main market at 10 PM. Two people were injured.",
        "Accident on highway 48 near the flyover. Traffic blocked.",
        "Fire broke out in the old building near station road.",
    ] * 60
    suspicious  = ["I think something bad happened maybe", "not sure but maybe danger"] * 50
    report_df = pd.DataFrame({
        "text":  fake_reports + real_reports + suspicious,
        "label": [0]*120 + [2]*180 + [1]*100
    }).sample(frac=1, random_state=42)
    report_df.to_csv("data/report_training_data.csv", index=False)
    print("  report_training_data.csv written.")

    # Reporter data
    reporter_df = pd.DataFrame({
        "account_age_days":         np.random.exponential(200, n),
        "past_reports_total":       np.random.poisson(5, n),
        "past_reports_verified":    np.random.poisson(3, n),
        "past_reports_fake":        np.random.poisson(0.5, n),
        "accuracy_ratio":           np.random.beta(4, 2, n),
        "geo_consistency_score":    np.random.beta(5, 1, n),
        "device_trust_score":       np.random.beta(4, 2, n),
        "report_frequency_7d":      np.random.poisson(1, n),
        "corroboration_score":      np.random.beta(2, 3, n),
        "time_since_last_report_h": np.random.exponential(48, n),
        "is_verified_user":         np.random.randint(0, 2, n),
        "media_attached":           np.random.randint(0, 2, n),
        "cross_platform_match":     np.random.beta(2, 5, n),
    })
    reporter_df["is_trusted"] = (
        (reporter_df["accuracy_ratio"] > 0.5) &
        (reporter_df["account_age_days"] > 30) &
        (reporter_df["past_reports_fake"] < 2)
    ).astype(int)
    reporter_df.to_csv("data/reporter_training_data.csv", index=False)
    print("  reporter_training_data.csv written.")


if __name__ == "__main__":
    os.makedirs("data", exist_ok=True)

    # Generate synthetic data if real data doesn't exist
    if not os.path.exists("data/zone_training_data.csv"):
        generate_synthetic_data()

    train_zone_model("data/zone_training_data.csv")
    train_report_verifier("data/report_training_data.csv", use_bert=False)
    train_trust_scorer("data/reporter_training_data.csv")

    print("\n=== All models trained successfully ===")
    print("Start the ML service with: uvicorn ml.api.main:app --reload --port 8000")
