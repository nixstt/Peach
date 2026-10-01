import { FormEvent, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createMeeting } from "@/lib/api";

function localToUtcIso(value: string): string {
  return new Date(value).toISOString();
}

function formatDetail(detail: unknown): string {
  if (typeof detail === "string") {
    return detail;
  }
  if (Array.isArray(detail)) {
    return detail
      .map((item) => {
        if (item && typeof item === "object" && "msg" in item) {
          return String((item as { msg: string }).msg);
        }
        return JSON.stringify(item);
      })
      .join(" ");
  }
  return "Could not create meeting.";
}

type MeetingFormProps = {
  onCreated: () => Promise<void>;
};

export function MeetingForm({ onCreated }: MeetingFormProps) {
  const [title, setTitle] = useState("");
  const [startsAt, setStartsAt] = useState("");
  const [endsAt, setEndsAt] = useState("");
  const [attendeeCount, setAttendeeCount] = useState("1");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      await createMeeting({
        title,
        starts_at: localToUtcIso(startsAt),
        ends_at: localToUtcIso(endsAt),
        attendee_count: Number(attendeeCount),
      });
      setTitle("");
      setStartsAt("");
      setEndsAt("");
      setAttendeeCount("1");
      await onCreated();
    } catch (err) {
      const detail = (err as { detail?: unknown }).detail;
      setError(formatDetail(detail));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Create meeting</CardTitle>
      </CardHeader>
      <CardContent>
        <form className="grid gap-4 md:grid-cols-2" onSubmit={onSubmit}>
          <div className="grid gap-2 md:col-span-2">
            <Label htmlFor="title">Title</Label>
            <Input
              id="title"
              name="title"
              required
              maxLength={200}
              value={title}
              onChange={(event) => setTitle(event.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="starts_at">Starts at</Label>
            <Input
              id="starts_at"
              name="starts_at"
              type="datetime-local"
              required
              value={startsAt}
              onChange={(event) => setStartsAt(event.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="ends_at">Ends at</Label>
            <Input
              id="ends_at"
              name="ends_at"
              type="datetime-local"
              required
              value={endsAt}
              onChange={(event) => setEndsAt(event.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="attendee_count">Attendee count</Label>
            <Input
              id="attendee_count"
              name="attendee_count"
              type="number"
              min={1}
              required
              value={attendeeCount}
              onChange={(event) => setAttendeeCount(event.target.value)}
            />
          </div>
          <div className="flex items-end">
            <Button type="submit" disabled={submitting}>
              {submitting ? "Saving..." : "Create"}
            </Button>
          </div>
          {error ? <p className="text-destructive md:col-span-2">{error}</p> : null}
        </form>
      </CardContent>
    </Card>
  );
}
