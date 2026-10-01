import { useCallback, useEffect, useState } from "react";
import { Layout } from "@/components/layout";
import { MeetingForm } from "@/components/meeting-form";
import { MeetingTable } from "@/components/meeting-table";
import { getMeetings, type Meeting } from "@/lib/api";

export default function App() {
  const [meetings, setMeetings] = useState<Meeting[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    const data = await getMeetings();
    setMeetings(data);
    setLoadError(null);
  }, []);

  useEffect(() => {
    refresh().catch(() => setLoadError("Could not load meetings."));
  }, [refresh]);

  return (
    <Layout>
      <header>
        <h1 className="text-3xl font-semibold tracking-tight">Meetings</h1>
        <p className="text-muted-foreground">List upcoming meetings and create a new one.</p>
      </header>
      {loadError ? <p className="text-destructive">{loadError}</p> : null}
      <MeetingForm onCreated={refresh} />
      <MeetingTable meetings={meetings} />
    </Layout>
  );
}
