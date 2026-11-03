import json
import logging

from app.ai import agenda_lambda
from app.ai.agenda import ParsedAgenda


def test_lambda_rejects_missing_authentication() -> None:
    response = agenda_lambda.handler(
        {"headers": {}, "body": json.dumps({"text": "Agenda"})},
        object(),
    )

    assert response["statusCode"] == 401
    assert json.loads(response["body"])["error"]


def test_lambda_rejects_long_text_before_model_call(monkeypatch) -> None:
    monkeypatch.setattr(agenda_lambda, "verify_cognito_token", lambda token: {"sub": "user-1"})
    monkeypatch.setattr(
        agenda_lambda,
        "parse_agenda",
        lambda *args: (_ for _ in ()).throw(AssertionError("model should not be called")),
    )
    event = {
        "headers": {"authorization": "Bearer token"},
        "body": json.dumps({"text": "x" * 10_001, "today": "2026-11-03", "tz": "Europe/Kyiv"}),
    }

    response = agenda_lambda.handler(event, object())

    assert response["statusCode"] == 413


def test_lambda_rejects_missing_price_configuration_before_model_call(monkeypatch) -> None:
    monkeypatch.delenv("PARSER_INPUT_USD_PER_MILLION", raising=False)
    monkeypatch.delenv("PARSER_OUTPUT_USD_PER_MILLION", raising=False)
    monkeypatch.setattr(agenda_lambda, "verify_cognito_token", lambda token: {"sub": "user-1"})
    monkeypatch.setattr(
        agenda_lambda,
        "parse_agenda",
        lambda *args: (_ for _ in ()).throw(AssertionError("model should not be called")),
    )
    event = {
        "headers": {"authorization": "Bearer token"},
        "body": json.dumps({"text": "Agenda", "today": "2026-11-03", "tz": "Europe/Kyiv"}),
    }

    response = agenda_lambda.handler(event, object())

    assert response["statusCode"] == 500
    assert "not configured" in json.loads(response["body"])["error"]


def test_lambda_returns_agenda_and_logs_usage_without_text(monkeypatch, caplog) -> None:
    monkeypatch.setenv("PARSER_MODEL", "anthropic.claude-opus-5-5")
    monkeypatch.setenv("PARSER_INPUT_USD_PER_MILLION", "15")
    monkeypatch.setenv("PARSER_OUTPUT_USD_PER_MILLION", "75")
    monkeypatch.setattr(agenda_lambda, "verify_cognito_token", lambda token: {"sub": "user-1"})
    monkeypatch.setattr(
        agenda_lambda,
        "parse_agenda",
        lambda text, today, tz: (
            ParsedAgenda(items=[{"topic": "Roadmap"}], language="en"),
            {"input_tokens": 123, "output_tokens": 45},
        ),
    )
    event = {
        "headers": {"authorization": "Bearer token"},
        "body": json.dumps(
            {
                "text": "Private pasted note",
                "today": "2026-11-03",
                "tz": "Europe/Kyiv",
            }
        ),
    }

    with caplog.at_level(logging.INFO):
        response = agenda_lambda.handler(event, object())

    assert response["statusCode"] == 200
    assert json.loads(response["body"])["agenda"]["items"][0]["topic"] == "Roadmap"
    record = next(
        json.loads(entry.message)
        for entry in caplog.records
        if '"event":"agenda_parsed"' in entry.message
    )
    assert record["user"] == "user-1"
    assert record["model"] == "anthropic.claude-opus-5-5"
    assert record["prompt_version"] == "agenda-v1"
    assert record["input_tokens"] == 123
    assert record["output_tokens"] == 45
    assert record["latency_ms"] >= 0
    assert record["cost_usd"] == 0.00522
    assert "Private pasted note" not in json.dumps(record)
