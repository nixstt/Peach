import csv
import io
import re
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select

from app.db import SessionLocal
from app.models.meeting import Meeting
from app.schemas.meeting import to_utc_z

_WEEK_PATTERN = re.compile(r"^\d{4}-W\d{2}$")
_REPORT_TIMEZONE = ZoneInfo("Europe/Kyiv")
_CSV_FIELDS = [
    "section",
    "week",
    "metric",
    "value",
    "title",
    "starts_at",
    "duration_hours",
    "participants",
]


def build_weekly_report(week: str) -> bytes:
    """Query meetings for an ISO week (for example, '2026-W40') and return a CSV."""
    if not _WEEK_PATTERN.fullmatch(week):
        raise ValueError("week must use YYYY-Www ISO week format")

    try:
        year, week_number = int(week[:4]), int(week[-2:])
        week_start_date = date.fromisocalendar(year, week_number, 1)
    except ValueError as exc:
        raise ValueError(f"invalid ISO week: {week}") from exc

    previous_week = week_start_date - timedelta(days=7)
    current_start = datetime.combine(week_start_date, time.min, tzinfo=_REPORT_TIMEZONE).astimezone(
        UTC
    )
    previous_start = datetime.combine(previous_week, time.min, tzinfo=_REPORT_TIMEZONE).astimezone(
        UTC
    )
    next_start = datetime.combine(
        week_start_date + timedelta(days=7), time.min, tzinfo=_REPORT_TIMEZONE
    ).astimezone(UTC)
    previous_week_label = previous_week.strftime("%G-W%V")

    with SessionLocal() as db:
        meetings = db.scalars(
            select(Meeting)
            .where(Meeting.starts_at >= previous_start, Meeting.starts_at < next_start)
            .order_by(Meeting.starts_at.asc(), Meeting.id.asc())
        ).all()

    this_week_meetings = [meeting for meeting in meetings if meeting.starts_at >= current_start]
    previous_week_meetings = [meeting for meeting in meetings if meeting.starts_at < current_start]

    def total_hours(rows: list[Meeting]) -> float:
        return sum((meeting.ends_at - meeting.starts_at).total_seconds() for meeting in rows) / 3600

    current_hours = total_hours(this_week_meetings)
    previous_hours = total_hours(previous_week_meetings)
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=_CSV_FIELDS, lineterminator="\n")
    writer.writeheader()

    for label, rows, hours in (
        (week, this_week_meetings, current_hours),
        (previous_week_label, previous_week_meetings, previous_hours),
    ):
        writer.writerow(
            {
                "section": "summary",
                "week": label,
                "metric": "meeting_count",
                "value": len(rows),
            }
        )
        writer.writerow(
            {
                "section": "summary",
                "week": label,
                "metric": "total_duration_hours",
                "value": f"{hours:.2f}",
            }
        )

    writer.writerow(
        {
            "section": "change",
            "week": week,
            "metric": "meeting_count",
            "value": len(this_week_meetings) - len(previous_week_meetings),
        }
    )
    writer.writerow(
        {
            "section": "change",
            "week": week,
            "metric": "total_duration_hours",
            "value": f"{current_hours - previous_hours:.2f}",
        }
    )
    longest = sorted(
        this_week_meetings,
        key=lambda meeting: (
            -(meeting.ends_at - meeting.starts_at).total_seconds(),
            meeting.starts_at,
            meeting.id,
        ),
    )[:5]
    for meeting in longest:
        duration_hours = (meeting.ends_at - meeting.starts_at).total_seconds() / 3600
        writer.writerow(
            {
                "section": "meeting",
                "week": week,
                "title": meeting.title,
                "starts_at": to_utc_z(meeting.starts_at),
                "duration_hours": f"{duration_hours:.2f}",
                "participants": meeting.attendee_count,
            }
        )

    return output.getvalue().encode("utf-8")
