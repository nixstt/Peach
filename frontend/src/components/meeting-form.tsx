import { type FormEvent, useState } from "react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { MeetingInput } from "@/api";
import { toUtcZ } from "@/lib/dates";

type MeetingFormProps = {
  onCreate: (input: MeetingInput) => Promise<void>;
};

export function MeetingForm({ onCreate }: MeetingFormProps) {
  const [title, setTitle] = useState("");
  const [starts, setStarts] = useState("");
  const [ends, setEnds] = useState("");
  const [attendees, setAttendees] = useState("1");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    const count = Number(attendees);
    if (!Number.isInteger(count) || count < 1) {
      setError("Attendee count has to be at least 1.");
      return;
    }
    const startDate = new Date(starts);
    const endDate = new Date(ends);
    if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) {
      setError("Both times are required.");
      return;
    }
    if (endDate <= startDate) {
      setError("The meeting has to end after it starts.");
      return;
    }

    setPending(true);
    try {
      await onCreate({
        title: title.trim(),
        starts_at: toUtcZ(starts),
        ends_at: toUtcZ(ends),
        attendee_count: count,
      });
      setTitle("");
      setStarts("");
      setEnds("");
      setAttendees("1");
    } catch (caught) {
      setError(
        caught instanceof Error ? caught.message : "Could not add the meeting.",
      );
    } finally {
      setPending(false);
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>New meeting</CardTitle>
      </CardHeader>
      <CardContent>
        <form className="flex flex-col gap-4" onSubmit={handleSubmit}>
          <div className="flex flex-col gap-2">
            <Label htmlFor="title">Title</Label>
            <Input
              id="title"
              value={title}
              maxLength={200}
              required
              onChange={(event) => setTitle(event.target.value)}
            />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="starts">Starts</Label>
            <Input
              id="starts"
              type="datetime-local"
              value={starts}
              required
              onChange={(event) => setStarts(event.target.value)}
            />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="ends">Ends</Label>
            <Input
              id="ends"
              type="datetime-local"
              value={ends}
              required
              onChange={(event) => setEnds(event.target.value)}
            />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="attendees">Attendees</Label>
            <Input
              id="attendees"
              type="number"
              min={1}
              step={1}
              value={attendees}
              required
              onChange={(event) => setAttendees(event.target.value)}
            />
          </div>
          {error ? (
            <p className="text-sm text-rust" role="alert">
              {error}
            </p>
          ) : null}
          <Button type="submit" disabled={pending}>
            {pending ? "Adding…" : "Add meeting"}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
