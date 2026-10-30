import { useEffect } from "react";
import { useAuth } from "react-oidc-context";

/**
 * /auth/callback/ — Cognito redirects here with ?code=…&state=….
 * react-oidc-context detects the callback automatically when it
 * renders inside <AuthProvider>; this component just shows a spinner
 * while that exchange completes, then sends the user home.
 */
export function AuthCallbackPage() {
  const auth = useAuth();

  useEffect(() => {
    if (auth.isAuthenticated) {
      window.location.replace("/");
    }
  }, [auth.isAuthenticated]);

  if (auth.error) {
    return (
      <main className="mx-auto flex max-w-sm flex-col items-center justify-center py-32">
        <p className="text-rust">Sign-in failed: {auth.error.message}</p>
        <a href="/login/" className="mt-4 underline">
          Try again
        </a>
      </main>
    );
  }

  return (
    <main className="mx-auto flex max-w-sm flex-col items-center justify-center py-32">
      <p className="font-serif text-4xl tracking-tight">Spry</p>
      <p className="mt-4 text-mist">Completing sign-in…</p>
    </main>
  );
}
