import type { UserManagerSettings } from "oidc-client-ts";

const region = import.meta.env.VITE_AWS_REGION || "eu-north-1";
const userPoolId = import.meta.env.VITE_COGNITO_USER_POOL_ID as string;
const authority =
  (import.meta.env.VITE_COGNITO_AUTHORITY as string) ||
  (userPoolId
    ? `https://cognito-idp.${region}.amazonaws.com/${userPoolId}`
    : "");

const clientId = (import.meta.env.VITE_COGNITO_CLIENT_ID as string) || "";
const redirectUri =
  (import.meta.env.VITE_AUTH_REDIRECT_URI as string) ||
  (typeof window !== "undefined"
    ? `${window.location.origin}/auth/callback/`
    : "http://localhost:3000/auth/callback/");

if (!authority || !clientId) {
  console.warn(
    "Auth env vars missing. Set VITE_COGNITO_AUTHORITY (or VITE_COGNITO_USER_POOL_ID) and VITE_COGNITO_CLIENT_ID.",
  );
}

export const oidcConfig: UserManagerSettings = {
  authority,
  client_id: clientId,
  redirect_uri: redirectUri,
  response_type: "code",
  scope: "openid email profile",
  // Cognito does not implement the standard OIDC end-session endpoint.
  // We handle sign-out manually via the /logout endpoint.
  automaticSilentRenew: true,
  loadUserInfo: true,
};

/** Build the Cognito hosted-UI logout URL. */
export function cognitoLogoutUrl(
  cognitoDomain: string,
  appClientId: string,
  logoutUri: string,
): string {
  if (!cognitoDomain || !appClientId) return "/";
  const domain = cognitoDomain.startsWith("http")
    ? cognitoDomain
    : `https://${cognitoDomain}`;
  return `${domain}/logout?client_id=${encodeURIComponent(appClientId)}&logout_uri=${encodeURIComponent(logoutUri)}`;
}
