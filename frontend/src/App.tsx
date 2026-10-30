import { useCallback, useEffect, useState } from "react";
import { useAuth } from "react-oidc-context";

import {
  createMeeting,
  listMeetings,
  setAccessToken,
  type Meeting,
  type MeetingInput,
} from "@/api";
import { MeetingForm } from "@/components/meeting-form";
import { MeetingTable } from "@/components/meeting-table";
import { WeekSummary } from "@/components/week-summary";
import { AuthCallbackPage } from "@/pages/AuthCallback";
import { LoginPage } from "@/pages/Login";

const rawCognitoDomain = (import.meta.env.VITE_COGNITO_DOMAIN as string) || "";
const cognitoClientId = (import.meta.env.VITE_COGNITO_CLIENT_ID as string) || "";
const region = (import.meta.env.VITE_AWS_REGION as string) || "eu-north-1";

function getCognitoDomainUrl(): string {
  if (!rawCognitoDomain) return "";
  if (rawCognitoDomain.startsWith("http://") || rawCognitoDomain.startsWith("https://")) {
    return rawCognitoDomain.replace(/\/$/, "");
  }
  return `https://${rawCognitoDomain}.auth.${region}.amazoncognito.com`;
}

function buildLogoutUrl(): string {
  const domain = getCognitoDomainUrl();
  if (!domain || !cognitoClientId) return "/";
  const logoutUri =
    (import.meta.env.VITE_AUTH_LOGOUT_URI as string) ||
    (typeof window !== "undefined" ? `${window.location.origin}/` : "/");
  return `${domain}/logout?client_id=${encodeURIComponent(cognitoClientId)}&logout_uri=${encodeURIComponent(logoutUri)}`;
}

function Header() {
  const auth = useAuth();

  async function handleSignOut() {
    await auth.removeUser();
    window.location.href = buildLogoutUrl();
  }

  const userEmail =
    auth.user?.profile?.email ||
    (auth.user?.profile as Record<string, unknown>)?.username?.toString() ||
    "Signed in";

  return (
    <header className="mb-8 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
      <div>
        <p className="font-serif text-4xl tracking-tight">Spry</p>
        <h1 className="mt-1 text-lg text-mist">Meetings</h1>
      </div>
      <div className="flex flex-wrap items-center gap-3 pt-1">
        {auth.isAuthenticated ? (
          <>
            <span className="text-sm font-medium text-mist" title={userEmail}>
              {userEmail}
            </span>
            <button
              type="button"
              onClick={() => void handleSignOut()}
              className="rounded-md bg-stone px-3 py-1.5 text-sm text-white transition-opacity hover:opacity-90"
            >
              Sign out
            </button>
          </>
        ) : (
          <>
            <button
              type="button"
              onClick={() =>
                void auth.signinRedirect({
                  extraQueryParams: { identity_provider: "Google" },
                })
              }
              className="rounded-md border border-stone/30 bg-white px-3 py-1.5 text-sm font-medium text-stone transition hover:bg-stone/5"
            >
              Continue with Google
            </button>
            <a
              href="/login/"
              className="rounded-md bg-stone px-3 py-1.5 text-sm font-medium text-white transition-opacity hover:opacity-90"
            >
              Sign in
            </a>
          </>
        )}
      </div>
    </header>
  );
}

function MainApp() {
  const auth = useAuth();
  const [meetings, setMeetings] = useState<Meeting[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setAccessToken(auth.user?.access_token ?? null);
  }, [auth.user]);

  const refresh = useCallback(async () => {
    const rows = await listMeetings();
    setMeetings(rows);
  }, []);

  useEffect(() => {
    let active = true;
    refresh()
      .catch((caught: unknown) => {
        if (active) {
          setError(
            caught instanceof Error
              ? caught.message
              : "Could not load meetings.",
          );
        }
      })
      .finally(() => {
        if (active) {
          setLoading(false);
        }
      });
    return () => {
      active = false;
    };
  }, [refresh, auth.isAuthenticated]);

  async function onCreate(input: MeetingInput) {
    await createMeeting(input);
    await refresh();
  }

  return (
    <main className="mx-auto max-w-5xl px-5 py-10">
      <Header />
      {error ? (
        <p
          className="mb-6 rounded-md border border-rust/30 bg-white px-4 py-3 text-sm text-rust"
          role="alert"
        >
          {error}
        </p>
      ) : null}
      <WeekSummary meetings={meetings} />
      <div className="mt-6 grid items-start gap-6 lg:grid-cols-[300px_1fr]">
        <MeetingForm onCreate={onCreate} />
        <MeetingTable meetings={meetings} loading={loading} />
      </div>
      <p className="mt-6 text-xs text-mist">
        Times are shown in your local zone. The API stores UTC.
      </p>
    </main>
  );
}

export function App() {
  const path = window.location.pathname;

  if (path === "/login/" || path === "/login") {
    return <LoginPage />;
  }
  if (path.startsWith("/auth/callback")) {
    return <AuthCallbackPage />;
  }
  return <MainApp />;
}
