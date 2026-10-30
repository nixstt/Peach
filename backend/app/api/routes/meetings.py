from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.auth import verify_token
from app.db import get_db
from app.schemas.meeting import MeetingCreate, MeetingRead
from app.services import meetings

router = APIRouter(prefix="/api")


@router.get("/meetings", response_model=list[MeetingRead])
def get_meetings(db: Session = Depends(get_db), _: dict = Depends(verify_token)) -> list[MeetingRead]:
    return meetings.list_meetings(db)


@router.post("/meetings", response_model=MeetingRead, status_code=201)
def post_meeting(body: MeetingCreate, db: Session = Depends(get_db), _: dict = Depends(verify_token)) -> MeetingRead:
    return meetings.create_meeting(db, body)
