import { useEffect } from "react";
import { useAuth } from "react-oidc-context";

/**
 * /login/ — immediately kicks off the Cognito-hosted sign-in flow.
 * The library stores a PKCE code_verifier and a random state here
 * before redirecting, so the flow MUST start on this page (not by
 * opening the Cognito URL directly).
 */
export function LoginPage() {
  const auth = useAuth();

  useEffect(() => {
    if (!auth.isAuthenticated && !auth.isLoading && !auth.activeNavigator) {
      void auth.signinRedirect();
    }
  }, [auth]);

  return (
    <main className="mx-auto flex max-w-sm flex-col items-center justify-center py-32">
      <p className="font-serif text-4xl tracking-tight">Spry</p>
      <p className="mt-4 text-mist">Redirecting to sign-in…</p>
    </main>
  );
}
