/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_URL: string;
  readonly VITE_COGNITO_AUTHORITY: string;
  readonly VITE_COGNITO_CLIENT_ID: string;
  readonly VITE_COGNITO_DOMAIN: string;
  readonly VITE_AUTH_REDIRECT_URI: string;
  readonly VITE_AUTH_LOGOUT_URI: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
