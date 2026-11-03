import json
import os
import sys
from datetime import date

from app.ai.agenda import _client, parse_agenda


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "parse"
    model = os.environ.get("PARSER_MODEL", "anthropic.claude-opus-5-5")
    if command == "hello":
        response = _client().messages.create(
            model=model,
            max_tokens=128,
            system="Reply with a short greeting.",
            messages=[{"role": "user", "content": "Say hello to Spry."}],
        )
        print(
            json.dumps(
                {
                    "text": "".join(
                        block.text for block in response.content if block.type == "text"
                    ),
                    "stop_reason": response.stop_reason,
                    "usage": response.usage.model_dump(),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return
    if command != "parse":
        raise SystemExit("Use `hello` or `parse`.")

    text = os.environ.get("TEXT", "")
    agenda, usage = parse_agenda(
        text,
        date.fromisoformat(os.environ.get("TODAY", date.today().isoformat())),
        os.environ.get("TZ", "Europe/Kyiv"),
    )
    print(
        json.dumps(
            {"agenda": agenda.model_dump(mode="json"), "usage": usage},
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
