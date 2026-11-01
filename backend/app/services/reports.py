from datetime import UTC, datetime
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from app.models.report_request import ReportRequest

_REPORT_TIMEZONE = ZoneInfo("Europe/Kyiv")


def request_current_weekly_report(db: Session, requester: dict[str, Any]) -> tuple[int, str]:
    requester_sub = requester.get("sub")
    if not isinstance(requester_sub, str) or not requester_sub:
        raise ValueError("The authenticated user has no subject identifier")

    requested_at = datetime.now(UTC)
    today = requested_at.astimezone(_REPORT_TIMEZONE).date()
    iso_year, iso_week, _ = today.isocalendar()
    week = f"{iso_year:04d}-W{iso_week:02d}"
    request = ReportRequest(
        week=week,
        requester_sub=requester_sub,
        created_at=requested_at,
    )
    db.add(request)
    db.commit()
    db.refresh(request)
    return request.id, request.week
