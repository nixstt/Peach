import json
import logging
import os
from datetime import UTC, datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

import boto3
from sqlalchemy import select

from app.db import SessionLocal
from app.models.report_request import ReportRequest
from app.reports.weekly import build_weekly_report

log = logging.getLogger()
log.setLevel(logging.INFO)
s3 = boto3.client("s3")
_REPORT_TIMEZONE = ZoneInfo("Europe/Kyiv")


def _previous_iso_week() -> str:
    today = datetime.now(_REPORT_TIMEZONE).date()
    this_monday = today - timedelta(days=today.isoweekday() - 1)
    previous_monday = this_monday - timedelta(days=7)
    iso_year, iso_week, _ = previous_monday.isocalendar()
    return f"{iso_year:04d}-W{iso_week:02d}"


def _put_report(week: str) -> None:
    report = build_weekly_report(week)
    s3.put_object(
        Bucket=os.environ["REPORTS_BUCKET"],
        Key=f"reports/{week}.csv",
        Body=report,
        ContentType="text/csv; charset=utf-8",
    )


def detect_trigger(event: dict[str, Any]) -> str:
    records = event.get("Records")
    if isinstance(records, list) and records:
        try:
            body = json.loads(records[0]["body"])
        except (KeyError, TypeError, json.JSONDecodeError):
            return "sqs"
        if body.get("source") == "schedule":
            return "schedule"
        return "sqs"
    source = event.get("source")
    if source == "schedule":
        return "schedule"
    if source == "outbox-poller":
        return "outbox"
    return "direct"


def _process_outbox() -> int:
    processed = 0
    with SessionLocal() as db:
        requests = db.scalars(
            select(ReportRequest)
            .where(ReportRequest.processed_at.is_(None))
            .order_by(ReportRequest.created_at.asc(), ReportRequest.id.asc())
            .limit(10)
            .with_for_update(skip_locked=True)
        ).all()
        for request in requests:
            _put_report(request.week)
            request.processed_at = datetime.now(UTC)
            processed += 1
        db.commit()
    return processed


def _handle_payload(payload: dict[str, Any]) -> None:
    week = payload.get("week")
    if week is None:
        week = _previous_iso_week()
    if not isinstance(week, str):
        raise ValueError("week must be a YYYY-Www string or null")
    _put_report(week)


def handler(event: dict[str, Any], context: object) -> dict[str, int | str]:
    trigger = detect_trigger(event)
    records = event.get("Records")
    if isinstance(records, list) and records:
        first_payload = json.loads(records[0]["body"])
        week = first_payload.get("week")
    else:
        week = event.get("week")
    if week is None and event.get("source") != "outbox-poller":
        week = _previous_iso_week()
    log.info(
        "report-builder triggered trigger=%s week=%s",
        trigger,
        week,
    )

    if isinstance(records, list):
        for record in records:
            payload = json.loads(record["body"])
            _handle_payload(payload)
        return {"processed": len(records)}

    if event.get("source") == "outbox-poller":
        count = _process_outbox()
        log.info("report-outbox processed count=%s", count)
        return {"processed": count}

    _handle_payload(event)
    return {"processed": 1}
