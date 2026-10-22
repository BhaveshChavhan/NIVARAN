"""
Red Zone Predictor — Model 1
Uses XGBoost for tabular features + LSTM for time-series patterns.
Outputs a risk score (0-1) + zone label (green / orange / red) per geo-cell.
"""

import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report
import joblib
import os

# ── Optional LSTM branch (requires TensorFlow) ──────────────────────────────
try:
    import tensorflow as tf
    from tensorflow.keras.models import Sequential
    from tensorflow.keras.layers import LSTM, Dense, Dropout
    LSTM_AVAILABLE = True
except ImportError:
    LSTM_AVAILABLE = False

# ── Config ───────────────────────────────────────────────────────────────────
RISK_THRESHOLDS = {"green": 0.35, "orange": 0.65}   # < green → safe, > orange → red
MODEL_DIR = "saved_models"
os.makedirs(MODEL_DIR, exist_ok=True)


# ── Feature engineering ──────────────────────────────────────────────────────
def build_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Expected raw columns:
        latitude, longitude, timestamp,
        news_crime_count, news_violence_count,
        social_media_alert_count, social_media_sentiment_score,
        gov_report_count, past_incident_count,
        time_of_day_hour, day_of_week, is_weekend,
        population_density, weather_severity
    """
    df = df.copy()

    # Temporal features
    df["hour_sin"] = np.sin(2 * np.pi * df["time_of_day_hour"] / 24)
    df["hour_cos"] = np.cos(2 * np.pi * df["time_of_day_hour"] / 24)
    df["day_sin"]  = np.sin(2 * np.pi * df["day_of_week"] / 7)
    df["day_cos"]  = np.cos(2 * np.pi * df["day_of_week"] / 7)

    # Composite scores
    df["media_risk_index"]   = (
        df["news_crime_count"] * 0.4 +
        df["news_violence_count"] * 0.4 +
        df["social_media_alert_count"] * 0.2
    )
    df["historical_risk"]    = df["past_incident_count"] / (df["past_incident_count"].max() + 1e-9)
    df["social_sentiment"]   = 1 - df["social_media_sentiment_score"]  # flip: lower sentiment = higher risk

    return df


FEATURE_COLS = [
    "media_risk_index", "historical_risk", "social_sentiment",
    "gov_report_count", "population_density", "weather_severity",
    "hour_sin", "hour_cos", "day_sin", "day_cos", "is_weekend"
]


# ── XGBoost model ────────────────────────────────────────────────────────────
class RedZoneXGBModel:
    def __init__(self):
        self.model = xgb.XGBClassifier(
            n_estimators=300,
            max_depth=6,
            learning_rate=0.05,
            subsample=0.8,
            colsample_bytree=0.8,
            use_label_encoder=False,
            eval_metric="mlogloss",
            random_state=42
        )
        self.scaler = StandardScaler()
        self.is_trained = False

    def fit(self, df: pd.DataFrame, label_col="risk_label"):
        df = build_features(df)
        X = df[FEATURE_COLS].fillna(0)
        # Encode labels: green=0, orange=1, red=2
        label_map = {"green": 0, "orange": 1, "red": 2}
        y = df[label_col].map(label_map)

        X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.2, stratify=y, random_state=42)
        X_train_sc = self.scaler.fit_transform(X_train)
        X_val_sc   = self.scaler.transform(X_val)

        self.model.fit(
            X_train_sc, y_train,
            eval_set=[(X_val_sc, y_val)],
            verbose=50
        )
        self.is_trained = True

        preds = self.model.predict(X_val_sc)
        print(classification_report(y_val, preds, target_names=["green", "orange", "red"]))

    def predict(self, df: pd.DataFrame) -> dict:
        df = build_features(df)
        X = df[FEATURE_COLS].fillna(0)
        X_sc = self.scaler.transform(X)
        proba = self.model.predict_proba(X_sc)   # shape (n, 3)

        risk_scores = proba[:, 1] * 0.5 + proba[:, 2]   # weighted: orange=0.5, red=1.0
        labels = []
        for s in risk_scores:
            if s < RISK_THRESHOLDS["green"]:
                labels.append("green")
            elif s < RISK_THRESHOLDS["orange"]:
                labels.append("orange")
            else:
                labels.append("red")

        return {
            "risk_scores":   risk_scores.tolist(),
            "risk_labels":   labels,
            "probabilities": proba.tolist()   # [p_green, p_orange, p_red]
        }

    def save(self, path=None):
        path = path or os.path.join(MODEL_DIR, "red_zone_xgb.pkl")
        joblib.dump({"model": self.model, "scaler": self.scaler}, path)
        print(f"Saved to {path}")

    def load(self, path=None):
        path = path or os.path.join(MODEL_DIR, "red_zone_xgb.pkl")
        obj = joblib.load(path)
        self.model = obj["model"]
        self.scaler = obj["scaler"]
        self.is_trained = True


# ── LSTM time-series branch (optional) ──────────────────────────────────────
class RedZoneLSTMModel:
    """
    Reads a rolling window of T timesteps per geo-cell.
    X shape: (samples, T=24, n_features)
    """
    def __init__(self, timesteps=24, n_features=len(FEATURE_COLS)):
        self.timesteps  = timesteps
        self.n_features = n_features
        self.model      = None
        self.scaler     = StandardScaler()

    def build(self):
        model = Sequential([
            LSTM(64, return_sequences=True, input_shape=(self.timesteps, self.n_features)),
            Dropout(0.2),
            LSTM(32),
            Dropout(0.2),
            Dense(16, activation="relu"),
            Dense(3, activation="softmax")   # green / orange / red
        ])
        model.compile(optimizer="adam", loss="sparse_categorical_crossentropy", metrics=["accuracy"])
        self.model = model

    def fit(self, X: np.ndarray, y: np.ndarray, epochs=20, batch_size=32):
        """X: (samples, timesteps, features), y: (samples,) with 0/1/2 labels"""
        if self.model is None:
            self.build()
        n, t, f = X.shape
        X_flat = X.reshape(-1, f)
        X_flat = self.scaler.fit_transform(X_flat)
        X = X_flat.reshape(n, t, f)
        self.model.fit(X, y, epochs=epochs, batch_size=batch_size, validation_split=0.2)

    def predict(self, X: np.ndarray) -> dict:
        n, t, f = X.shape
        X_flat = X.reshape(-1, f)
        X_flat = self.scaler.transform(X_flat)
        X = X_flat.reshape(n, t, f)
        proba = self.model.predict(X)
        labels_idx = np.argmax(proba, axis=1)
        label_names = ["green", "orange", "red"]
        return {
            "risk_labels":   [label_names[i] for i in labels_idx],
            "probabilities": proba.tolist()
        }

    def save(self, path=None):
        path = path or os.path.join(MODEL_DIR, "red_zone_lstm")
        self.model.save(path)
        joblib.dump(self.scaler, path + "_scaler.pkl")

    def load(self, path=None):
        path = path or os.path.join(MODEL_DIR, "red_zone_lstm")
        self.model = tf.keras.models.load_model(path)
        self.scaler = joblib.load(path + "_scaler.pkl")


# ── Ensemble (XGB + LSTM) ────────────────────────────────────────────────────
class RedZoneEnsemble:
    """
    Weights XGB and LSTM predictions.
    Falls back to XGB-only when LSTM is unavailable.
    """
    def __init__(self, xgb_weight=0.6, lstm_weight=0.4):
        self.xgb_model  = RedZoneXGBModel()
        self.lstm_model = RedZoneLSTMModel() if LSTM_AVAILABLE else None
        self.xgb_weight = xgb_weight
        self.lstm_weight = lstm_weight if LSTM_AVAILABLE else 0

    def predict_tabular(self, df: pd.DataFrame) -> dict:
        return self.xgb_model.predict(df)

    def predict_ensemble(self, df: pd.DataFrame, X_seq: np.ndarray = None) -> dict:
        xgb_out = self.xgb_model.predict(df)
        if self.lstm_model and X_seq is not None:
            lstm_out = self.lstm_model.predict(X_seq)
            xgb_p  = np.array(xgb_out["probabilities"])
            lstm_p = np.array(lstm_out["probabilities"])
            combined = self.xgb_weight * xgb_p + self.lstm_weight * lstm_p
        else:
            combined = np.array(xgb_out["probabilities"])

        risk_scores = combined[:, 1] * 0.5 + combined[:, 2]
        labels = []
        for s in risk_scores:
            if s < RISK_THRESHOLDS["green"]:
                labels.append("green")
            elif s < RISK_THRESHOLDS["orange"]:
                labels.append("orange")
            else:
                labels.append("red")

        return {
            "risk_scores":   risk_scores.tolist(),
            "risk_labels":   labels,
            "probabilities": combined.tolist()
        }
