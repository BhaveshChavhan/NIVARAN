"""
Data Ingestion Pipeline
Fetches from: News RSS/API · Twitter/X API · Government open data · Past incidents (blockchain DB)
Normalises, geo-tags, deduplicates, and returns a DataFrame ready for model inference.
"""

import os
import re
import time
import hashlib
import logging
from datetime import datetime, timedelta, timezone
from dataclasses import dataclass, field
from typing import Optional

import requests
import pandas as pd
import numpy as np

# ── Optional heavy deps ──────────────────────────────────────────────────────
try:
    import feedparser          # pip install feedparser
    FEEDPARSER_OK = True
except ImportError:
    FEEDPARSER_OK = False

try:
    from geopy.geocoders import Nominatim
    from geopy.exc import GeocoderTimedOut
    GEOPY_OK = True
except ImportError:
    GEOPY_OK = False

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)


# ── Config dataclass ─────────────────────────────────────────────────────────
@dataclass
class IngestionConfig:
    # Twitter / X
    twitter_bearer_token: str = os.getenv("TWITTER_BEARER_TOKEN", "")
    twitter_keywords: list = field(default_factory=lambda: [
        "crime", "accident", "robbery", "attack", "shooting",
        "fire", "flood", "riot", "explosion", "emergency"
    ])

    # News RSS feeds (free, no key needed)
    news_rss_feeds: list = field(default_factory=lambda: [
        "https://timesofindia.indiatimes.com/rssfeeds/-2128936835.cms",
        "https://www.thehindu.com/news/feeder/default.rss",
        "https://feeds.feedburner.com/ndtvnews-india-news",
        # Add regional feeds for your city/state
    ])

    # GNews API (free tier: 100 req/day)  https://gnews.io
    gnews_api_key: str = os.getenv("GNEWS_API_KEY", "")
    gnews_keywords: str = "crime OR accident OR emergency OR attack OR fire"

    # Government open data (India examples; swap for your region)
    govt_endpoints: list = field(default_factory=lambda: [
        "https://data.gov.in/api/datastore/resource.json?resource_id=PLACEHOLDER_ID&limit=100",
    ])
    govt_api_key: str = os.getenv("GOVT_DATA_API_KEY", "")

    # Your backend (past incidents from blockchain DB)
    backend_url: str = os.getenv("BACKEND_URL", "http://localhost:3000")
    backend_api_key: str = os.getenv("BACKEND_API_KEY", "")

    # Geo
    default_city: str = "Mumbai, India"
    geo_radius_km: float = 50.0

    # Rate limiting
    request_timeout: int = 10
    backoff_seconds: float = 1.0


# ── Geo helper ───────────────────────────────────────────────────────────────
class GeoTagger:
    def __init__(self, city=None):
        self._cache: dict[str, tuple] = {}
        self._geocoder = Nominatim(user_agent="safety-app-ingestion") if GEOPY_OK else None
        self.default_city = city or "Mumbai, India"

    def tag(self, text: str) -> tuple[Optional[float], Optional[float]]:
        """Very lightweight: look for known city/area names in text."""
        if not GEOPY_OK:
            return (None, None)
        key = text[:120]
        if key in self._cache:
            return self._cache[key]

        # Try to geocode first 120 chars that contain a place
        try:
            loc = self._geocoder.geocode(self.default_city, timeout=5)
            result = (loc.latitude, loc.longitude) if loc else (None, None)
        except (GeocoderTimedOut, Exception):
            result = (None, None)

        self._cache[key] = result
        return result


# ── News ingestion ────────────────────────────────────────────────────────────
class NewsIngester:
    def __init__(self, cfg: IngestionConfig):
        self.cfg = cfg
        self.geo = GeoTagger(cfg.default_city)

    def fetch_rss(self) -> list[dict]:
        if not FEEDPARSER_OK:
            logger.warning("feedparser not installed; skipping RSS. pip install feedparser")
            return []
        rows = []
        for url in self.cfg.news_rss_feeds:
            try:
                feed = feedparser.parse(url)
                for entry in feed.entries[:50]:
                    text = entry.get("summary", entry.get("title", ""))
                    lat, lon = self.geo.tag(text)
                    rows.append({
                        "source":    "news_rss",
                        "text":      text,
                        "title":     entry.get("title", ""),
                        "timestamp": entry.get("published", datetime.now(timezone.utc).isoformat()),
                        "latitude":  lat,
                        "longitude": lon,
                        "url":       entry.get("link", ""),
                        "_hash":     hashlib.md5(text.encode()).hexdigest(),
                    })
            except Exception as e:
                logger.warning(f"RSS {url}: {e}")
        return rows

    def fetch_gnews(self) -> list[dict]:
        if not self.cfg.gnews_api_key:
            return []
        url = (
            f"https://gnews.io/api/v4/search?q={self.cfg.gnews_keywords}"
            f"&lang=en&country=in&max=50&apikey={self.cfg.gnews_api_key}"
        )
        try:
            r = requests.get(url, timeout=self.cfg.request_timeout)
            r.raise_for_status()
            articles = r.json().get("articles", [])
            rows = []
            for a in articles:
                text = a.get("description", a.get("title", ""))
                lat, lon = self.geo.tag(text)
                rows.append({
                    "source": "gnews",
                    "text": text,
                    "title": a.get("title", ""),
                    "timestamp": a.get("publishedAt", datetime.now(timezone.utc).isoformat()),
                    "latitude": lat,
                    "longitude": lon,
                    "url": a.get("url", ""),
                    "_hash": hashlib.md5(text.encode()).hexdigest(),
                })
            return rows
        except Exception as e:
            logger.warning(f"GNews: {e}")
            return []


# ── Social media ingestion ────────────────────────────────────────────────────
class SocialMediaIngester:
    def __init__(self, cfg: IngestionConfig):
        self.cfg = cfg

    def fetch_twitter_recent(self) -> list[dict]:
        if not self.cfg.twitter_bearer_token:
            logger.warning("TWITTER_BEARER_TOKEN not set; skipping social fetch.")
            return []

        query = " OR ".join(self.cfg.twitter_keywords) + " lang:en -is:retweet"
        url   = "https://api.twitter.com/2/tweets/search/recent"
        headers = {"Authorization": f"Bearer {self.cfg.twitter_bearer_token}"}
        params  = {
            "query": query,
            "max_results": 100,
            "tweet.fields": "created_at,geo,public_metrics,lang",
            "expansions": "geo.place_id",
            "place.fields": "geo,name,country_code"
        }
        try:
            r = requests.get(url, headers=headers, params=params, timeout=self.cfg.request_timeout)
            r.raise_for_status()
            data = r.json()
            tweets = data.get("data", [])
            places = {p["id"]: p for p in data.get("includes", {}).get("places", [])}
            rows = []
            for t in tweets:
                place_id = t.get("geo", {}).get("place_id")
                place    = places.get(place_id, {})
                geo      = place.get("geo", {}).get("bbox", [None, None, None, None])
                lat = (geo[1] + geo[3]) / 2 if geo[1] else None
                lon = (geo[0] + geo[2]) / 2 if geo[0] else None
                rows.append({
                    "source":    "twitter",
                    "text":      t["text"],
                    "title":     "",
                    "timestamp": t.get("created_at", datetime.now(timezone.utc).isoformat()),
                    "latitude":  lat,
                    "longitude": lon,
                    "url":       f"https://twitter.com/i/web/status/{t['id']}",
                    "_hash":     hashlib.md5(t["text"].encode()).hexdigest(),
                    "like_count":    t.get("public_metrics", {}).get("like_count", 0),
                    "retweet_count": t.get("public_metrics", {}).get("retweet_count", 0),
                })
            return rows
        except Exception as e:
            logger.warning(f"Twitter API: {e}")
            return []


# ── Government data ───────────────────────────────────────────────────────────
class GovtDataIngester:
    def __init__(self, cfg: IngestionConfig):
        self.cfg = cfg

    def fetch(self) -> list[dict]:
        rows = []
        headers = {}
        if self.cfg.govt_api_key:
            headers["api-key"] = self.cfg.govt_api_key
        for endpoint in self.cfg.govt_endpoints:
            if "PLACEHOLDER" in endpoint:
                continue
            try:
                r = requests.get(endpoint, headers=headers, timeout=self.cfg.request_timeout)
                r.raise_for_status()
                records = r.json().get("records", [])
                for rec in records:
                    rows.append({
                        "source":    "govt",
                        "text":      str(rec),
                        "title":     rec.get("title", ""),
                        "timestamp": rec.get("date", datetime.now(timezone.utc).isoformat()),
                        "latitude":  rec.get("latitude"),
                        "longitude": rec.get("longitude"),
                        "_hash":     hashlib.md5(str(rec).encode()).hexdigest(),
                    })
            except Exception as e:
                logger.warning(f"Govt endpoint {endpoint}: {e}")
        return rows


# ── Past incident fetcher (from your blockchain-backed backend) ───────────────
class PastIncidentFetcher:
    def __init__(self, cfg: IngestionConfig):
        self.cfg = cfg

    def fetch(self, days_back=30) -> list[dict]:
        since = (datetime.now(timezone.utc) - timedelta(days=days_back)).isoformat()
        url   = f"{self.cfg.backend_url}/api/incidents"
        headers = {}
        if self.cfg.backend_api_key:
            headers["x-api-key"] = self.cfg.backend_api_key
        try:
            r = requests.get(url, headers=headers, params={"since": since}, timeout=self.cfg.request_timeout)
            r.raise_for_status()
            incidents = r.json()
            rows = []
            for inc in incidents:
                rows.append({
                    "source":    "blockchain_db",
                    "text":      inc.get("description", ""),
                    "title":     inc.get("type", ""),
                    "timestamp": inc.get("created_at", ""),
                    "latitude":  inc.get("latitude"),
                    "longitude": inc.get("longitude"),
                    "_hash":     inc.get("hash", hashlib.md5(str(inc).encode()).hexdigest()),
                    "verified":  inc.get("verified", False),
                })
            return rows
        except Exception as e:
            logger.warning(f"Backend incident fetch: {e}")
            return []


# ── Master pipeline ───────────────────────────────────────────────────────────
class DataIngestionPipeline:
    def __init__(self, cfg: IngestionConfig | None = None):
        self.cfg    = cfg or IngestionConfig()
        self.news   = NewsIngester(self.cfg)
        self.social = SocialMediaIngester(self.cfg)
        self.govt   = GovtDataIngester(self.cfg)
        self.past   = PastIncidentFetcher(self.cfg)

    def run(self) -> pd.DataFrame:
        logger.info("Starting data ingestion…")
        rows = []
        rows += self.news.fetch_rss()
        rows += self.news.fetch_gnews()
        rows += self.social.fetch_twitter_recent()
        rows += self.govt.fetch()
        rows += self.past.fetch()

        if not rows:
            logger.warning("No data fetched — returning empty DataFrame.")
            return pd.DataFrame()

        df = pd.DataFrame(rows)
        df = self._deduplicate(df)
        df = self._normalise(df)
        df = self._add_keyword_counts(df)
        logger.info(f"Ingestion complete: {len(df)} rows after deduplication.")
        return df

    def _deduplicate(self, df: pd.DataFrame) -> pd.DataFrame:
        if "_hash" in df.columns:
            df = df.drop_duplicates(subset="_hash")
        return df.reset_index(drop=True)

    def _normalise(self, df: pd.DataFrame) -> pd.DataFrame:
        df["timestamp"] = pd.to_datetime(df["timestamp"], errors="coerce", utc=True)
        df["text"]      = df["text"].fillna("").str.strip().str.lower()
        df["latitude"]  = pd.to_numeric(df["latitude"],  errors="coerce")
        df["longitude"] = pd.to_numeric(df["longitude"], errors="coerce")
        now = datetime.now(timezone.utc)
        df["time_of_day_hour"] = df["timestamp"].dt.hour.fillna(now.hour)
        df["day_of_week"]      = df["timestamp"].dt.dayofweek.fillna(now.weekday())
        df["is_weekend"]       = (df["day_of_week"] >= 5).astype(int)
        return df

    # Simple keyword count features for Model 1
    CRIME_WORDS    = re.compile(r"\b(crime|robbery|theft|murder|assault|stabbing|shooting|rape|attack)\b")
    VIOLENCE_WORDS = re.compile(r"\b(riot|bomb|explosion|fire|violence|accident|crash|flood|disaster)\b")
    ALERT_WORDS    = re.compile(r"\b(danger|unsafe|alert|warning|emergency|police|ambulance)\b")

    def _add_keyword_counts(self, df: pd.DataFrame) -> pd.DataFrame:
        df["news_crime_count"]           = df["text"].apply(lambda t: len(self.CRIME_WORDS.findall(t)))
        df["news_violence_count"]        = df["text"].apply(lambda t: len(self.VIOLENCE_WORDS.findall(t)))
        df["social_media_alert_count"]   = df["text"].apply(lambda t: len(self.ALERT_WORDS.findall(t)))
        # Placeholder: sentiment requires a sentiment model; default neutral
        df["social_media_sentiment_score"] = 0.5
        df["gov_report_count"]           = (df["source"] == "govt").astype(int)
        df["past_incident_count"]        = (df["source"] == "blockchain_db").astype(int)
        df["population_density"]         = 0.5    # inject from your geo DB
        df["weather_severity"]           = 0.0    # inject from weather API
        return df
