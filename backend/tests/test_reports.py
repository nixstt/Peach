import csv
import io
import re
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import delete, select

from app.db import SessionLocal
from app.main import app
from app.models.meeting import Meeting
from app.models.report_request import ReportRequest
from app.reports.weekly import build_weekly_report


@pytest.fixture
def clean_report_data():
    with SessionLocal() as db:
        db.execute(delete(ReportRequest))
        db.execute(delete(Meeting))
        db.commit()
    yield
    with SessionLocal() as db:
        db.execute(delete(ReportRequest))
        db.execute(delete(Meeting))
        db.commit()


def _meeting(title: str, starts_at: datetime, hours: float, attendees: int) -> Meeting:
    return Meeting(
        title=title,
        starts_at=starts_at,
        ends_at=starts_at + timedelta(hours=hours),
        attendee_count=attendees,
    )


def test_build_weekly_report_has_comparison_and_five_longest(clean_report_data) -> None:
    current_monday = datetime(2026, 9, 28, tzinfo=UTC)
    previous_monday = current_monday - timedelta(days=7)
    rows = [
        _meeting("Current 1", current_monday, 2, 3),
        _meeting("Current 2", current_monday + timedelta(days=1), 5, 6),
        _meeting("Current 3", current_monday + timedelta(days=2), 1, 2),
        _meeting("Current 4", current_monday + timedelta(days=3), 3, 4),
        _meeting("Current 5", current_monday + timedelta(days=4), 4, 5),
        _meeting("Current 6", current_monday + timedelta(days=5), 0.5, 7),
        _meeting("Sunday in Kyiv", datetime(2026, 9, 27, 22, tzinfo=UTC), 0.25, 8),
        _meeting("Previous 1", previous_monday, 1.5, 2),
        _meeting("Previous 2", previous_monday + timedelta(days=1), 1.5, 3),
    ]
    with SessionLocal() as db:
        db.add_all(rows)
        db.commit()

    report = build_weekly_report("2026-W40")
    parsed = list(csv.DictReader(io.StringIO(report.decode("utf-8"))))
    summary = {
        (row["week"], row["metric"]): row["value"] for row in parsed if row["section"] == "summary"
    }
    changes = {row["metric"]: row["value"] for row in parsed if row["section"] == "change"}
    top_meetings = [row for row in parsed if row["section"] == "meeting"]

    assert summary[("2026-W40", "meeting_count")] == "7"
    assert summary[("2026-W40", "total_duration_hours")] == "15.75"
    assert summary[("2026-W39", "meeting_count")] == "2"
    assert summary[("2026-W39", "total_duration_hours")] == "3.00"
    assert changes == {"meeting_count": "5", "total_duration_hours": "12.75"}
    assert [row["title"] for row in top_meetings] == [
        "Current 2",
        "Current 5",
        "Current 4",
        "Current 1",
        "Current 3",
    ]
    assert top_meetings[0]["participants"] == "6"
    assert build_weekly_report("2026-W40") == report


@pytest.mark.parametrize("week", ["", "2026-40", "2026-W00", "2025-W53"])
def test_build_weekly_report_rejects_invalid_iso_week(clean_report_data, week: str) -> None:
    with pytest.raises(ValueError):
        build_weekly_report(week)


def test_report_request_is_persisted_for_current_iso_week(clean_report_data) -> None:
    response = TestClient(app).post("/api/reports/weekly")

    assert response.status_code == 202
    result = response.json()
    assert result["status"] == "queued"
    assert re.fullmatch(r"\d{4}-W\d{2}", result["week"])
    with SessionLocal() as db:
        request = db.scalar(select(ReportRequest).where(ReportRequest.id == result["request_id"]))
    assert request is not None
    assert request.week == result["week"]
    assert request.processed_at is None
