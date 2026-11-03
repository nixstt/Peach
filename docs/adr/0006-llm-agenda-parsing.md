# ADR 0006: LLM agenda parsing

- **Status:** Accepted
- **Date:** 2026-11-03

## Context

Users paste agendas from emails, chats, and notes. The text is external and may contain misleading instructions. The application has no NAT gateway, and each model call has a measurable token cost.

## Decision

Use `anthropic.claude-opus-5-5` through Amazon Bedrock Mantle. Run an authenticated, non-VPC Lambda URL so inference does not require NAT or a VPC interface endpoint. Pass the user's date and IANA time zone, ask the model to call one typed tool, validate the result with Pydantic, and retry once on invalid output. The parser never writes. The browser presents editable suggestions, then sends the final agenda and original suggestion to the authenticated API for storage. Log the user, model, prompt version, token counts, latency, cost, and status without logging pasted text. Set a $5 monthly AWS Budget alert.

## Alternatives considered

- **Call Bedrock from the API through a VPC endpoint:** loses because it adds a recurring endpoint charge to a low-volume feature.
- **Call the Claude API directly:** loses because Bedrock keeps inference in the AWS account and uses the existing AWS identity and billing boundary.
- **Use regular expressions:** loses because pasted agendas vary in format and language, and regex does not reliably extract owners, dates, and action items.

## Consequences

The approximate cost per parse is `(input_tokens × input_price + output_tokens × output_price) / 1,000,000`; the deployed rate parameters must match the selected model's current us-east-1 price. Model failure or throttling leaves the manual form available, and the rest of Spry keeps working. The parser's public URL is protected by Cognito-token verification, a 10,000-character input limit, and a $5 monthly budget alert.
