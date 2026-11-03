"""
JWT verification for Cognito access tokens.

The JWKS are fetched once per cold start and cached in memory.
Per-request validation checks signature, expiry, issuer, and client_id.
Without a valid token, the API returns 401.
"""

import os
from functools import lru_cache
from typing import Any

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient
from jwt.exceptions import PyJWKClientError

_bearer = HTTPBearer(auto_error=False)


class CognitoAuthError(Exception):
    pass


@lru_cache(maxsize=1)
def _jwks_client() -> PyJWKClient:
    """Return a cached JWKS client for the configured user pool."""
    pool_id = os.environ.get("COGNITO_USER_POOL_ID", "")
    if not pool_id:
        raise RuntimeError("COGNITO_USER_POOL_ID is not set")
    region = os.environ.get("AWS_REGION", "eu-north-1")
    jwks_url = f"https://cognito-idp.{region}.amazonaws.com/{pool_id}" f"/.well-known/jwks.json"
    return PyJWKClient(jwks_url, cache_keys=True)


def verify_cognito_token(authorization: str) -> dict[str, Any]:
    if not isinstance(authorization, str):
        raise CognitoAuthError("Missing or invalid Authorization header.")
    scheme, separator, token = authorization.partition(" ")
    if scheme.casefold() != "bearer" or not separator or not token.strip():
        raise CognitoAuthError("Missing or invalid Authorization header.")

    pool_id = os.environ.get("COGNITO_USER_POOL_ID", "")
    client_id = os.environ.get("COGNITO_CLIENT_ID", "")
    if not pool_id or not client_id:
        raise CognitoAuthError("Auth not configured on server.")

    region = os.environ.get("AWS_REGION", "eu-north-1")
    token = token.strip()
    try:
        signing_key = _jwks_client().get_signing_key_from_jwt(token)
        payload: dict[str, Any] = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            issuer=f"https://cognito-idp.{region}.amazonaws.com/{pool_id}",
            options={"verify_aud": False},
        )
    except (jwt.PyJWTError, PyJWKClientError, ValueError) as exc:
        raise CognitoAuthError("Invalid or expired token.") from exc

    if (
        payload.get("client_id") != client_id
        or payload.get("token_use") != "access"
        or not isinstance(payload.get("sub"), str)
    ):
        raise CognitoAuthError("Token not issued for this client.")
    return payload


def verify_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> dict[str, Any]:
    """
    FastAPI dependency. Raises 401 if the token is missing, expired,
    has the wrong issuer, or has the wrong client_id (audience).
    Returns the decoded payload on success.
    """
    if credentials is None or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header.",
        )

    try:
        return verify_cognito_token(f"Bearer {credentials.credentials}")
    except CognitoAuthError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc)) from exc
