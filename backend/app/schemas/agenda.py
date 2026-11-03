from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.ai.agenda import ParsedAgenda


class AgendaCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    agenda: ParsedAgenda
    ai_suggestion: ParsedAgenda | None = None
    model: str | None = Field(default=None, min_length=1, max_length=200)
    prompt_version: str | None = Field(default=None, min_length=1, max_length=100)

    @model_validator(mode="after")
    def check_suggestion_metadata(self) -> "AgendaCreate":
        if (self.ai_suggestion is None) != (self.model is None) or (self.ai_suggestion is None) != (
            self.prompt_version is None
        ):
            raise ValueError("AI suggestion, model, and prompt_version must be provided together")
        return self


class AgendaRead(BaseModel):
    id: int
    agenda: dict[str, Any]
    ai_suggestion: dict[str, Any] | None
    model: str | None
    prompt_version: str | None
    created_at: datetime


class AgendaParseRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    text: str = Field(max_length=10_000)
    today: str = Field(min_length=10, max_length=10)
    tz: str = Field(min_length=1, max_length=100)

    @model_validator(mode="after")
    def validate_date(self) -> "AgendaParseRequest":
        from datetime import date

        date.fromisoformat(self.today)
        return self
