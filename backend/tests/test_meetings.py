import pytest
from fastapi.testclient import TestClient
from sqlalchemy import delete

from app.db import SessionLocal
from app.main import app
from app.models.meeting import Meeting


@pytest.fixture(autouse=True)
def _clean_meetings() -> None:
    db = SessionLocal()
    db.execute(delete(Meeting))
    db.commit()
    db.close()


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


def test_list_is_empty(client: TestClient) -> None:
    response = client.get("/api/meetings")
    assert response.status_code == 200
    assert response.json() == []


def test_create_and_list_sorted(client: TestClient) -> None:
    later = {
        "title": "  Later  ",
        "starts_at": "2026-10-02T10:00:00Z",
        "ends_at": "2026-10-02T11:00:00Z",
        "attendee_count": 2,
    }
    earlier = {
        "title": "Earlier",
        "starts_at": "2026-10-01T12:00:00+02:00",
        "ends_at": "2026-10-01T13:00:00+02:00",
        "attendee_count": 4,
    }
    created_later = client.post("/api/meetings", json=later)
    created_earlier = client.post("/api/meetings", json=earlier)
    assert created_later.status_code == 201
    assert created_earlier.status_code == 201
    assert created_later.json()["title"] == "Later"
    assert created_earlier.json()["starts_at"] == "2026-10-01T10:00:00Z"
    assert created_earlier.json()["ends_at"] == "2026-10-01T11:00:00Z"

    listed = client.get("/api/meetings")
    assert listed.status_code == 200
    titles = [row["title"] for row in listed.json()]
    assert titles == ["Earlier", "Later"]


def test_same_start_sorts_by_id(client: TestClient) -> None:
    body = {
        "title": "First",
        "starts_at": "2026-10-03T10:00:00Z",
        "ends_at": "2026-10-03T11:00:00Z",
        "attendee_count": 1,
    }
    first = client.post("/api/meetings", json=body).json()
    second = client.post("/api/meetings", json={**body, "title": "Second"}).json()
    ids = [row["id"] for row in client.get("/api/meetings").json()]
    assert ids == [first["id"], second["id"]]


@pytest.mark.parametrize(
    "body",
    [
        {
            "title": "   ",
            "starts_at": "2026-10-01T10:00:00Z",
            "ends_at": "2026-10-01T11:00:00Z",
            "attendee_count": 1,
        },
        {
            "title": "No zone",
            "starts_at": "2026-10-01T10:00:00",
            "ends_at": "2026-10-01T11:00:00Z",
            "attendee_count": 1,
        },
        {
            "title": "Backwards",
            "starts_at": "2026-10-01T11:00:00Z",
            "ends_at": "2026-10-01T10:00:00Z",
            "attendee_count": 1,
        },
        {
            "title": "Equal",
            "starts_at": "2026-10-01T10:00:00Z",
            "ends_at": "2026-10-01T10:00:00Z",
            "attendee_count": 1,
        },
        {
            "title": "Nobody",
            "starts_at": "2026-10-01T10:00:00Z",
            "ends_at": "2026-10-01T11:00:00Z",
            "attendee_count": 0,
        },
        {
            "id": 9,
            "title": "Has id",
            "starts_at": "2026-10-01T10:00:00Z",
            "ends_at": "2026-10-01T11:00:00Z",
            "attendee_count": 1,
        },
    ],
)
def test_rejects_invalid_body(client: TestClient, body: dict) -> None:
    response = client.post("/api/meetings", json=body)
    assert response.status_code == 422
    assert isinstance(response.json()["detail"], list)


def test_unauthenticated_request_rejected(client: TestClient) -> None:
    from app.auth import verify_token

    app.dependency_overrides.pop(verify_token, None)
    try:
        response = client.get("/api/meetings")
        assert response.status_code == 401
    finally:
        app.dependency_overrides[verify_token] = lambda: {
            "sub": "test-user-id",
            "client_id": "test-client-id",
            "email": "tester@example.com",
        }
