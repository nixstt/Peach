import { useCallback, useEffect, useState } from "react";

import {
  createMeeting,
  listMeetings,
  type Meeting,
  type MeetingInput,
} from "@/api";
import { MeetingForm } from "@/components/meeting-form";
import { MeetingTable } from "@/components/meeting-table";
import { WeekSummary } from "@/components/week-summary";

export function App() {
  const [meetings, setMeetings] = useState<Meeting[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

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
  }, [refresh]);

  async function onCreate(input: MeetingInput) {
    await createMeeting(input);
    await refresh();
  }

  return (
    <main className="mx-auto max-w-5xl px-5 py-10">
      <header className="mb-8">
        <p className="font-serif text-4xl tracking-tight">Spry</p>
        <h1 className="mt-1 text-lg text-mist">Meetings</h1>
      </header>
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
