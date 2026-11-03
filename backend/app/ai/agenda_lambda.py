import base64
import json
import logging
import os
import time
from datetime import date
from typing import Any

from pydantic import ValidationError

from app.ai.agenda import (
    MAX_TEXT_LENGTH,
    PROMPT_VERSION,
    AgendaModelBusyError,
    AgendaParseError,
    AgendaServiceError,
    cost_usd,
    parse_agenda,
)
from app.auth import CognitoAuthError, verify_cognito_token
from app.schemas.agenda import AgendaParseRequest

log = logging.getLogger()
log.setLevel(logging.INFO)


def _response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }


def handler(event: dict[str, Any], context: object) -> dict[str, Any]:
    raw_headers = event.get("headers")
    headers = (
        {str(key).lower(): value for key, value in raw_headers.items()}
        if isinstance(raw_headers, dict)
        else {}
    )
    try:
        user = verify_cognito_token(headers.get("authorization", ""))
    except CognitoAuthError:
        return _response(401, {"error": "A valid Cognito access token is required."})

    body = event.get("body")
    if event.get("isBase64Encoded"):
        try:
            body = base64.b64decode(body or "", validate=True).decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            return _response(400, {"error": "Request body must be valid UTF-8 JSON."})
    try:
        payload = json.loads(body or "")
    except (TypeError, json.JSONDecodeError):
        return _response(400, {"error": "Request body must be valid JSON."})
    if not isinstance(payload, dict):
        return _response(400, {"error": "Request body must be a JSON object."})

    text = payload.get("text")
    if not isinstance(text, str):
        return _response(400, {"error": "text must be a string."})
    if len(text) > MAX_TEXT_LENGTH:
        return _response(413, {"error": f"text must be {MAX_TEXT_LENGTH:,} characters or fewer."})
    try:
        request = AgendaParseRequest.model_validate(payload)
    except ValidationError:
        return _response(400, {"error": "today must be an ISO date and tz an IANA time zone."})
    today = date.fromisoformat(request.today)
    tz = request.tz
    text = request.text

    model = os.environ.get("PARSER_MODEL", "anthropic.claude-opus-5-5")
    usage = {"input_tokens": 0, "output_tokens": 0}
    try:
        cost_usd(model, usage)
    except (ArithmeticError, RuntimeError):
        log.error("Agenda parser token prices are missing or invalid")
        return _response(500, {"error": "The agenda parser is not configured correctly."})
    started = time.monotonic()
    status_code = 500
    try:
        agenda, usage = parse_agenda(text, today, tz)
        status_code = 200
    except AgendaModelBusyError as exc:
        status_code = 429
        error = str(exc)
        return _response(status_code, {"error": error})
    except AgendaServiceError as exc:
        usage = exc.usage
        status_code = 503
        error = str(exc)
        return _response(status_code, {"error": error})
    except AgendaParseError as exc:
        usage = exc.usage
        status_code = 422
        error = str(exc)
        return _response(status_code, {"error": error})
    finally:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        log.info(
            json.dumps(
                {
                    "event": "agenda_parsed",
                    "user": user["sub"],
                    "model": model,
                    "prompt_version": PROMPT_VERSION,
                    **usage,
                    "latency_ms": elapsed_ms,
                    "cost_usd": cost_usd(model, usage),
                    "status_code": status_code,
                },
                separators=(",", ":"),
            )
        )

    return _response(
        200,
        {
            "agenda": agenda.model_dump(mode="json"),
            "model": model,
            "prompt_version": PROMPT_VERSION,
        },
    )
