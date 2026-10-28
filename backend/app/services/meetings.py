from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.meeting import Meeting
from app.schemas.meeting import MeetingCreate, MeetingRead, to_utc_z


def list_meetings(db: Session) -> list[MeetingRead]:
    rows = db.scalars(select(Meeting).order_by(Meeting.starts_at.asc(), Meeting.id.asc())).all()
    return [
        MeetingRead(
            id=row.id,
            title=row.title,
            starts_at=to_utc_z(row.starts_at),
            ends_at=to_utc_z(row.ends_at),
            attendee_count=row.attendee_count,
        )
        for row in rows
    ]


def create_meeting(db: Session, data: MeetingCreate) -> MeetingRead:
    row = Meeting(
        title=data.title,
        starts_at=data.starts_at,
        ends_at=data.ends_at,
        attendee_count=data.attendee_count,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return MeetingRead(
        id=row.id,
        title=row.title,
        starts_at=to_utc_z(row.starts_at),
        ends_at=to_utc_z(row.ends_at),
        attendee_count=row.attendee_count,
    )
