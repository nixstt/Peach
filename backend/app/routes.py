from fastapi import APIRouter, Depends, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Meeting
from app.schemas import MeetingCreate, MeetingRead

router = APIRouter()


@router.get("/meetings", response_model=list[MeetingRead])
def list_meetings(db: Session = Depends(get_db)) -> list[Meeting]:
    stmt = select(Meeting).order_by(Meeting.starts_at.asc(), Meeting.id.asc())
    return list(db.scalars(stmt).all())


@router.post("/meetings", response_model=MeetingRead, status_code=status.HTTP_201_CREATED)
def create_meeting(payload: MeetingCreate, db: Session = Depends(get_db)) -> Meeting:
    meeting = Meeting(
        title=payload.title,
        starts_at=payload.starts_at,
        ends_at=payload.ends_at,
        attendee_count=payload.attendee_count,
    )
    db.add(meeting)
    db.commit()
    db.refresh(meeting)
    return meeting
