from sqlalchemy.orm import Session

from app.models.agenda import Agenda
from app.schemas.agenda import AgendaCreate, AgendaRead


def create_agenda(db: Session, data: AgendaCreate, user_sub: str) -> AgendaRead:
    row = Agenda(
        user_sub=user_sub,
        agenda=data.agenda.model_dump(mode="json"),
        ai_suggestion=(
            data.ai_suggestion.model_dump(mode="json") if data.ai_suggestion is not None else None
        ),
        model=data.model,
        prompt_version=data.prompt_version,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return AgendaRead(
        id=row.id,
        agenda=row.agenda,
        ai_suggestion=row.ai_suggestion,
        model=row.model,
        prompt_version=row.prompt_version,
        created_at=row.created_at,
    )
