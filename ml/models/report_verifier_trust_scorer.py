"""
Report Verifier — Model 2   (BERT-based text classifier)
Trust Scorer   — Model 3   (Random Forest on metadata signals)

Model 2: takes a user-submitted incident report text and
         classifies it as: credible / suspicious / fake

Model 3: scores the reporter's trustworthiness using:
         - account age, past report history, device signals,
           geo-consistency, cross-source corroboration, spam patterns
"""

import re
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report
import joblib
import os

try:
    from transformers import pipeline, AutoTokenizer, AutoModelForSequenceClassification
    import torch
    TRANSFORMERS_AVAILABLE = True
except ImportError:
    TRANSFORMERS_AVAILABLE = False

MODEL_DIR = "saved_models"
os.makedirs(MODEL_DIR, exist_ok=True)


# ══════════════════════════════════════════════════════════════════════════════
# MODEL 2 — REPORT VERIFIER (BERT classifier)
# ══════════════════════════════════════════════════════════════════════════════

class ReportVerifier:
    """
    Fine-tuned BERT on labelled incident reports.
    Labels: 0=fake, 1=suspicious, 2=credible
    Falls back to a rule-based baseline when transformers are not installed.
    """

    PRETRAINED = "distilbert-base-uncased"   # smaller, fast, good accuracy

    # ── Linguistic red-flags (rule-based fallback) ──────────────────────────
    SPAM_PATTERNS = [
        r"\b(click here|buy now|win prize|lottery|100% free)\b",
        r"(http|https|www\.)\S+",          # raw URLs in report text
        r"(.)\1{4,}",                       # repeated characters: "!!!!!!"
        r"\b(fuck|shit|bastard)\b",
        r"[A-Z]{8,}",                       # EXCESSIVE CAPS
    ]

    def __init__(self):
        self.classifier   = None
        self.tokenizer    = None
        self.use_bert     = False
        self._spam_re     = [re.compile(p, re.IGNORECASE) for p in self.SPAM_PATTERNS]

    # ── BERT fine-tuning ─────────────────────────────────────────────────────
    def fine_tune(self, texts, labels, epochs=3, model_name=None):
        """
        texts  : list[str]   — report text
        labels : list[int]   — 0 fake / 1 suspicious / 2 credible
        """
        if not TRANSFORMERS_AVAILABLE:
            raise RuntimeError("pip install transformers torch")

        from transformers import (
            AutoTokenizer, AutoModelForSequenceClassification,
            TrainingArguments, Trainer
        )
        import datasets

        model_name = model_name or self.PRETRAINED
        self.tokenizer = AutoTokenizer.from_pretrained(model_name)

        def tokenize(batch):
            return self.tokenizer(batch["text"], truncation=True, padding="max_length", max_length=256)

        ds = datasets.Dataset.from_dict({"text": texts, "label": labels})
        ds = ds.map(tokenize, batched=True)
        train_ds, val_ds = ds.train_test_split(test_size=0.15).values()

        bert_model = AutoModelForSequenceClassification.from_pretrained(model_name, num_labels=3)
        args = TrainingArguments(
            output_dir="./bert_report_verifier",
            num_train_epochs=epochs,
            per_device_train_batch_size=16,
            per_device_eval_batch_size=16,
            evaluation_strategy="epoch",
            save_strategy="epoch",
            load_best_model_at_end=True,
        )
        trainer = Trainer(model=bert_model, args=args, train_dataset=train_ds, eval_dataset=val_ds)
        trainer.train()
        trainer.save_model(os.path.join(MODEL_DIR, "bert_report_verifier"))
        self.tokenizer.save_pretrained(os.path.join(MODEL_DIR, "bert_report_verifier"))
        self._load_pipeline()

    def _load_pipeline(self):
        if not TRANSFORMERS_AVAILABLE:
            return
        path = os.path.join(MODEL_DIR, "bert_report_verifier")
        if os.path.exists(path):
            self.classifier = pipeline(
                "text-classification",
                model=path,
                tokenizer=path,
                top_k=None,
                device=0 if (TRANSFORMERS_AVAILABLE and torch.cuda.is_available()) else -1
            )
            self.use_bert = True

    def load(self):
        self._load_pipeline()

    # ── Inference ────────────────────────────────────────────────────────────
    def verify(self, text: str) -> dict:
        """Returns verdict + confidence scores for all three classes."""
        spam_flags = [bool(p.search(text)) for p in self._spam_re]
        spam_score = sum(spam_flags) / len(self._spam_re)

        if self.use_bert and self.classifier:
            results = self.classifier(text[:512])[0]   # safety truncation
            scores  = {r["label"]: r["score"] for r in results}
            label_map = {"LABEL_0": "fake", "LABEL_1": "suspicious", "LABEL_2": "credible"}
            named = {label_map.get(k, k): v for k, v in scores.items()}
        else:
            # Rule-based fallback
            named = self._rule_based(text, spam_score)

        verdict = max(named, key=named.get)
        return {
            "verdict":     verdict,
            "confidence":  named[verdict],
            "scores":      named,
            "spam_score":  spam_score,
            "spam_flags":  spam_flags
        }

    def _rule_based(self, text: str, spam_score: float) -> dict:
        """Lightweight heuristics when BERT is not available."""
        length = len(text.split())
        if spam_score > 0.4 or length < 5:
            return {"fake": 0.7, "suspicious": 0.2, "credible": 0.1}
        elif spam_score > 0.2 or length < 15:
            return {"fake": 0.2, "suspicious": 0.5, "credible": 0.3}
        else:
            return {"fake": 0.1, "suspicious": 0.2, "credible": 0.7}

    def batch_verify(self, texts: list[str]) -> list[dict]:
        return [self.verify(t) for t in texts]


# ══════════════════════════════════════════════════════════════════════════════
# MODEL 3 — TRUST SCORER (Random Forest on metadata)
# ══════════════════════════════════════════════════════════════════════════════

TRUST_FEATURE_COLS = [
    "account_age_days",         # how old is this user account
    "past_reports_total",       # total reports submitted
    "past_reports_verified",    # how many were confirmed accurate
    "past_reports_fake",        # how many were confirmed fake
    "accuracy_ratio",           # verified / (total + 1)
    "geo_consistency_score",    # 0-1: reported location matches user's usual area
    "device_trust_score",       # 0-1: derived from device fingerprint / OS
    "report_frequency_7d",      # reports in last 7 days (spam signal if very high)
    "corroboration_score",      # 0-1: how many other sources confirm this incident
    "time_since_last_report_h", # hours since last report (flood detection)
    "is_verified_user",         # boolean: passed KYC / phone verification
    "media_attached",           # boolean: photo/video attached to report
    "cross_platform_match",     # 0-1: similar event found in news/social media
]


class TrustScorer:
    def __init__(self):
        self.model   = RandomForestClassifier(
            n_estimators=200,
            max_depth=10,
            class_weight="balanced",
            random_state=42
        )
        self.scaler     = StandardScaler()
        self.is_trained = False

    def _engineer(self, df: pd.DataFrame) -> pd.DataFrame:
        df = df.copy()
        df["accuracy_ratio"] = df["past_reports_verified"] / (df["past_reports_total"] + 1)
        df["fake_ratio"]     = df["past_reports_fake"]     / (df["past_reports_total"] + 1)
        df["trust_momentum"] = df["accuracy_ratio"] - df["fake_ratio"]   # net trust signal
        return df

    def fit(self, df: pd.DataFrame, label_col="is_trusted"):
        """label_col: 1 = trustworthy reporter, 0 = untrustworthy"""
        df = self._engineer(df)
        cols = TRUST_FEATURE_COLS + ["trust_momentum", "fake_ratio"]
        X = df[cols].fillna(0)
        y = df[label_col]

        X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.2, random_state=42)
        X_train = self.scaler.fit_transform(X_train)
        X_val   = self.scaler.transform(X_val)

        self.model.fit(X_train, y_train)
        self.is_trained = True

        preds = self.model.predict(X_val)
        print(classification_report(y_val, preds, target_names=["untrustworthy", "trustworthy"]))

    def score(self, reporter_meta: dict) -> dict:
        """
        reporter_meta: dict with keys matching TRUST_FEATURE_COLS
        Returns trust_score (0-1), label, and feature importances.
        """
        df = pd.DataFrame([reporter_meta])
        df = self._engineer(df)
        cols = TRUST_FEATURE_COLS + ["trust_momentum", "fake_ratio"]
        X = df[cols].fillna(0)
        X_sc = self.scaler.transform(X)

        proba      = self.model.predict_proba(X_sc)[0]
        trust_prob = proba[1]
        label = "trusted" if trust_prob >= 0.6 else ("borderline" if trust_prob >= 0.4 else "flagged")

        # Top 3 most influential features
        importances = dict(zip(cols, self.model.feature_importances_))
        top_factors = sorted(importances, key=importances.get, reverse=True)[:3]

        return {
            "trust_score":  round(float(trust_prob), 3),
            "label":        label,
            "top_factors":  top_factors,
            "raw_proba":    {"untrusted": round(float(proba[0]), 3), "trusted": round(float(proba[1]), 3)}
        }

    def save(self, path=None):
        path = path or os.path.join(MODEL_DIR, "trust_scorer_rf.pkl")
        joblib.dump({"model": self.model, "scaler": self.scaler}, path)

    def load(self, path=None):
        path = path or os.path.join(MODEL_DIR, "trust_scorer_rf.pkl")
        obj = joblib.load(path)
        self.model   = obj["model"]
        self.scaler  = obj["scaler"]
        self.is_trained = True


# ══════════════════════════════════════════════════════════════════════════════
# COMBINED INCIDENT ANALYSER
# ══════════════════════════════════════════════════════════════════════════════

class IncidentAnalyser:
    """
    Wraps Model 2 + Model 3 into a single call.
    Returns a final verdict combining text credibility and reporter trust.
    """
    def __init__(self):
        self.verifier = ReportVerifier()
        self.scorer   = TrustScorer()

    def load_all(self):
        self.verifier.load()
        self.scorer.load()

    def analyse(self, report_text: str, reporter_meta: dict) -> dict:
        text_result  = self.verifier.verify(report_text)
        trust_result = self.scorer.score(reporter_meta)

        # Combine: weighted average
        text_credibility = text_result["scores"].get("credible", 0.5)
        trust_score      = trust_result["trust_score"]

        final_score = 0.55 * text_credibility + 0.45 * trust_score

        if final_score >= 0.65:
            final_verdict = "CONFIRMED_CREDIBLE"
        elif final_score >= 0.40:
            final_verdict = "NEEDS_REVIEW"
        else:
            final_verdict = "FLAGGED_FAKE"

        return {
            "final_verdict":  final_verdict,
            "final_score":    round(final_score, 3),
            "text_analysis":  text_result,
            "trust_analysis": trust_result
        }
