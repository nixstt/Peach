from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import verify_token
from app.db import get_db
from app.schemas.meeting import MeetingCreate, MeetingRead
from app.services import meetings, reports

router = APIRouter(prefix="/api")


@router.get("/meetings", response_model=list[MeetingRead])
def get_meetings(
    db: Session = Depends(get_db), _: dict = Depends(verify_token)
) -> list[MeetingRead]:
    return meetings.list_meetings(db)


@router.post("/meetings", response_model=MeetingRead, status_code=201)
def post_meeting(
    body: MeetingCreate, db: Session = Depends(get_db), _: dict = Depends(verify_token)
) -> MeetingRead:
    return meetings.create_meeting(db, body)


@router.post("/reports/weekly", status_code=202)
def post_weekly_report_request(
    db: Session = Depends(get_db), requester: dict = Depends(verify_token)
) -> dict[str, int | str]:
    try:
        request_id, week = reports.request_current_weekly_report(db, requester)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc
    return {"request_id": request_id, "week": week, "status": "queued"}
