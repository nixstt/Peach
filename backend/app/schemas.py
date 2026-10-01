from datetime import datetime, timezone

from pydantic import (
    AwareDatetime,
    BaseModel,
    Field,
    field_serializer,
    field_validator,
    model_validator,
)


def _to_utc_z(value: datetime) -> str:
    aware = value.astimezone(timezone.utc)
    return aware.strftime("%Y-%m-%dT%H:%M:%SZ")


class MeetingCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    starts_at: AwareDatetime
    ends_at: AwareDatetime
    attendee_count: int = Field(..., ge=1)

    @field_validator("title", mode="before")
    @classmethod
    def strip_title(cls, value: object) -> object:
        if isinstance(value, str):
            return value.strip()
        return value

    @model_validator(mode="after")
    def ends_after_starts(self) -> "MeetingCreate":
        if self.ends_at <= self.starts_at:
            raise ValueError("ends_at must be after starts_at")
        return self


class MeetingRead(BaseModel):
    id: int
    title: str
    starts_at: datetime
    ends_at: datetime
    attendee_count: int

    model_config = {"from_attributes": True}

    @field_serializer("starts_at", "ends_at")
    def serialize_datetimes(self, value: datetime) -> str:
        return _to_utc_z(value)
