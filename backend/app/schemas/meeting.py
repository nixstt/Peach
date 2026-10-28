from datetime import UTC, datetime
from typing import Annotated

from pydantic import BaseModel, BeforeValidator, ConfigDict, Field, model_validator


def to_utc_z(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def _strip(value: object) -> object:
    if isinstance(value, str):
        return value.strip()
    return value


class MeetingCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: Annotated[str, BeforeValidator(_strip), Field(min_length=1, max_length=200)]
    starts_at: datetime
    ends_at: datetime
    attendee_count: int = Field(ge=1)

    @model_validator(mode="after")
    def check_times(self) -> "MeetingCreate":
        if self.starts_at.tzinfo is None or self.starts_at.utcoffset() is None:
            raise ValueError("starts_at must include a timezone")
        if self.ends_at.tzinfo is None or self.ends_at.utcoffset() is None:
            raise ValueError("ends_at must include a timezone")
        self.starts_at = self.starts_at.astimezone(UTC)
        self.ends_at = self.ends_at.astimezone(UTC)
        if self.ends_at <= self.starts_at:
            raise ValueError("ends_at must be after starts_at")
        return self


class MeetingRead(BaseModel):
    id: int
    title: str
    starts_at: str
    ends_at: str
    attendee_count: int
