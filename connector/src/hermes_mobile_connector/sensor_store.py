"""Local SQLite store for sensor data (location + health).

The connector stores all sensor data locally — never on the cloud relay.
Tables are designed for efficient agent queries via MCP tools.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


@dataclass(frozen=True)
class LocationReading:
    latitude: float
    longitude: float
    altitude: float | None = None
    accuracy: float | None = None
    address: str | None = None
    recorded_at: str | None = None  # ISO8601; defaults to now


@dataclass(frozen=True)
class HealthSample:
    metric: str
    value: float
    unit: str
    start_at: str  # ISO8601
    end_at: str | None = None
    source: str = "healthkit"


@dataclass(frozen=True)
class CurrentLocation:
    latitude: float
    longitude: float
    altitude: float | None
    accuracy: float | None
    address: str | None
    recorded_at: str
    updated_at: str


@dataclass(frozen=True)
class LatestMetric:
    metric: str
    value: float
    unit: str
    updated_at: str


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS location_history (
    id          TEXT PRIMARY KEY,
    latitude    REAL NOT NULL,
    longitude   REAL NOT NULL,
    altitude    REAL,
    accuracy    REAL,
    address     TEXT,
    recorded_at TEXT NOT NULL,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE INDEX IF NOT EXISTS idx_location_history_time ON location_history(recorded_at DESC);

CREATE TABLE IF NOT EXISTS location_current (
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    latitude    REAL NOT NULL,
    longitude   REAL NOT NULL,
    altitude    REAL,
    accuracy    REAL,
    address     TEXT,
    recorded_at TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS health_samples (
    id         TEXT PRIMARY KEY,
    metric     TEXT NOT NULL,
    value      REAL NOT NULL,
    unit       TEXT NOT NULL,
    start_at   TEXT NOT NULL,
    end_at     TEXT,
    source     TEXT NOT NULL DEFAULT 'healthkit',
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE INDEX IF NOT EXISTS idx_health_samples_metric_time ON health_samples(metric, start_at DESC);

CREATE TABLE IF NOT EXISTS health_latest (
    metric     TEXT PRIMARY KEY,
    value      REAL NOT NULL,
    unit       TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
"""


class SensorStore:
    """SQLite-backed store for location and health sensor data."""

    def __init__(self, db_path: str | Path) -> None:
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(self.db_path), check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode = WAL")
        self._conn.execute("PRAGMA synchronous = NORMAL")
        self._conn.execute("PRAGMA foreign_keys = ON")
        self._conn.execute("PRAGMA busy_timeout = 5000")
        self._conn.executescript(SCHEMA_SQL)

    def close(self) -> None:
        self._conn.close()

    # ── Location ─────────────────────────────────────────────────

    def store_location(self, reading: LocationReading) -> str:
        """Store a location update in both history and current tables."""
        row_id = str(uuid4())
        recorded_at = reading.recorded_at or utcnow_iso()
        now = utcnow_iso()

        self._conn.execute(
            "INSERT INTO location_history (id, latitude, longitude, altitude, accuracy, address, recorded_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (row_id, reading.latitude, reading.longitude, reading.altitude, reading.accuracy, reading.address, recorded_at),
        )
        self._conn.execute(
            "INSERT INTO location_current (id, latitude, longitude, altitude, accuracy, address, recorded_at, updated_at) "
            "VALUES (1, ?, ?, ?, ?, ?, ?, ?) "
            "ON CONFLICT(id) DO UPDATE SET "
            "latitude=excluded.latitude, longitude=excluded.longitude, altitude=excluded.altitude, "
            "accuracy=excluded.accuracy, address=excluded.address, recorded_at=excluded.recorded_at, updated_at=excluded.updated_at",
            (reading.latitude, reading.longitude, reading.altitude, reading.accuracy, reading.address, recorded_at, now),
        )
        self._conn.commit()
        return row_id

    def get_current_location(self) -> CurrentLocation | None:
        row = self._conn.execute("SELECT * FROM location_current WHERE id = 1").fetchone()
        if row is None:
            return None
        return CurrentLocation(
            latitude=row["latitude"],
            longitude=row["longitude"],
            altitude=row["altitude"],
            accuracy=row["accuracy"],
            address=row["address"],
            recorded_at=row["recorded_at"],
            updated_at=row["updated_at"],
        )

    def get_location_history(self, *, since: str | None = None, limit: int = 50) -> list[dict]:
        if since:
            rows = self._conn.execute(
                "SELECT * FROM location_history WHERE recorded_at >= ? ORDER BY recorded_at DESC LIMIT ?",
                (since, limit),
            ).fetchall()
        else:
            rows = self._conn.execute(
                "SELECT * FROM location_history ORDER BY recorded_at DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return [dict(row) for row in rows]

    # ── Health ───────────────────────────────────────────────────

    def store_health_samples(self, samples: list[HealthSample]) -> int:
        """Store health samples and update latest metrics. Returns count stored."""
        now = utcnow_iso()
        stored = 0
        for sample in samples:
            row_id = str(uuid4())
            self._conn.execute(
                "INSERT INTO health_samples (id, metric, value, unit, start_at, end_at, source) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (row_id, sample.metric, sample.value, sample.unit, sample.start_at, sample.end_at, sample.source),
            )
            self._conn.execute(
                "INSERT INTO health_latest (metric, value, unit, updated_at) "
                "VALUES (?, ?, ?, ?) "
                "ON CONFLICT(metric) DO UPDATE SET value=excluded.value, unit=excluded.unit, updated_at=excluded.updated_at",
                (sample.metric, sample.value, sample.unit, now),
            )
            stored += 1
        self._conn.commit()
        return stored

    def get_latest_metrics(self) -> list[LatestMetric]:
        rows = self._conn.execute("SELECT * FROM health_latest ORDER BY metric").fetchall()
        return [
            LatestMetric(metric=row["metric"], value=row["value"], unit=row["unit"], updated_at=row["updated_at"])
            for row in rows
        ]

    def get_health_metric(self, metric: str, *, since: str | None = None, limit: int = 50) -> list[dict]:
        if since:
            rows = self._conn.execute(
                "SELECT * FROM health_samples WHERE metric = ? AND start_at >= ? ORDER BY start_at DESC LIMIT ?",
                (metric, since, limit),
            ).fetchall()
        else:
            rows = self._conn.execute(
                "SELECT * FROM health_samples WHERE metric = ? ORDER BY start_at DESC LIMIT ?",
                (metric, limit),
            ).fetchall()
        return [dict(row) for row in rows]

    def get_health_summary(self) -> dict:
        """Return a structured summary of all latest metrics."""
        metrics = self.get_latest_metrics()
        return {
            "metrics": {m.metric: {"value": m.value, "unit": m.unit, "updatedAt": m.updated_at} for m in metrics},
            "count": len(metrics),
        }

    # ── Maintenance ──────────────────────────────────────────────

    def prune_location_history(self, retention_days: int = 90) -> int:
        cutoff = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        # Rough cutoff: subtract days worth of seconds
        from datetime import timedelta
        cutoff_dt = datetime.now(timezone.utc) - timedelta(days=retention_days)
        cutoff = cutoff_dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        cursor = self._conn.execute("DELETE FROM location_history WHERE recorded_at < ?", (cutoff,))
        self._conn.commit()
        return cursor.rowcount

    def prune_health_samples(self, retention_days: int = 90) -> int:
        from datetime import timedelta
        cutoff_dt = datetime.now(timezone.utc) - timedelta(days=retention_days)
        cutoff = cutoff_dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        cursor = self._conn.execute("DELETE FROM health_samples WHERE start_at < ?", (cutoff,))
        self._conn.commit()
        return cursor.rowcount
