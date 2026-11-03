import { type FormEvent, useRef, useState } from "react";

import {
  AgendaParseError,
  createAgenda,
  parseAgenda,
  type ActionItem,
  type AgendaItem,
  type ParsedAgenda,
} from "@/api";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type ParsedSource = {
  suggestion: ParsedAgenda | null;
  model: string | null;
  promptVersion: string | null;
};

const emptyAgenda = (): ParsedAgenda => ({
  title: null,
  starts_at: null,
  duration_minutes: null,
  items: [],
  action_items: [],
  language: "en",
});

function localToday(): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const values = Object.fromEntries(
    parts.map(({ type, value }) => [type, value]),
  );
  return `${values.year}-${values.month}-${values.day}`;
}

function parseErrorMessage(error: unknown): string {
  if (error instanceof AgendaParseError) {
    if (error.status === 413) {
      return "That text is too long. Keep it under 10,000 characters, or enter the agenda by hand.";
    }
    if (error.status === 422) {
      return (
        error.message ||
        "The model could not find a usable agenda in that text."
      );
    }
    if (error.status === 429 || error.status === 503) {
      return "The agenda service is busy. Please try again later or enter the agenda by hand.";
    }
    return error.message;
  }
  if (error instanceof TypeError) {
    return "Could not reach the agenda service. Check your connection or enter the agenda by hand.";
  }
  return error instanceof Error ? error.message : "Could not parse the agenda.";
}

export function AgendaPasteForm() {
  const [text, setText] = useState("");
  const [draft, setDraft] = useState<ParsedAgenda | null>(null);
  const [source, setSource] = useState<ParsedSource | null>(null);
  const [edited, setEdited] = useState<Set<string>>(new Set());
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [saving, setSaving] = useState(false);
  const controller = useRef<AbortController | null>(null);

  function updateField<K extends keyof ParsedAgenda>(
    key: K,
    value: ParsedAgenda[K],
  ) {
    setDraft((current) => (current ? { ...current, [key]: value } : current));
    setEdited((current) => new Set(current).add(key));
  }

  function updateItem(index: number, key: keyof AgendaItem, value: string) {
    if (!draft) return;
    const items = draft.items.map((item, itemIndex) =>
      itemIndex === index
        ? {
            ...item,
            [key]:
              key === "minutes"
                ? value === ""
                  ? null
                  : Number(value)
                : value === ""
                  ? null
                  : value,
          }
        : item,
    );
    setDraft({ ...draft, items });
    setEdited((current) => new Set(current).add(`items.${index}.${key}`));
  }

  function updateAction(index: number, key: keyof ActionItem, value: string) {
    if (!draft) return;
    const actionItems = draft.action_items.map((item, itemIndex) =>
      itemIndex === index
        ? { ...item, [key]: value === "" ? null : value }
        : item,
    );
    setDraft({ ...draft, action_items: actionItems });
    setEdited((current) =>
      new Set(current).add(`action_items.${index}.${key}`),
    );
  }

  function suggested(path: string, value: unknown) {
    return source?.suggestion &&
      value !== null &&
      value !== "" &&
      !edited.has(path) ? (
      <span className="ml-2 rounded-full bg-spruce/10 px-2 py-0.5 text-xs text-spruce">
        Suggested
      </span>
    ) : null;
  }

  async function handleParse(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setMessage(null);
    controller.current?.abort();
    const activeController = new AbortController();
    controller.current = activeController;
    setPending(true);
    try {
      const result = await parseAgenda(
        text,
        localToday(),
        Intl.DateTimeFormat().resolvedOptions().timeZone,
        activeController.signal,
      );
      setDraft(result.agenda);
      setSource({
        suggestion: result.agenda,
        model: result.model,
        promptVersion: result.prompt_version,
      });
      setEdited(new Set());
    } catch (caught) {
      if (activeController.signal.aborted) {
        setMessage(
          "Parsing cancelled. You can try again or enter the agenda by hand.",
        );
      } else {
        setError(parseErrorMessage(caught));
      }
    } finally {
      if (controller.current === activeController) {
        controller.current = null;
        setPending(false);
      }
    }
  }

  function enterManually() {
    controller.current?.abort();
    setDraft(emptyAgenda());
    setSource({ suggestion: null, model: null, promptVersion: null });
    setEdited(new Set());
    setError(null);
    setMessage(null);
  }

  async function handleSave(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!draft) return;
    setError(null);
    setMessage(null);
    setSaving(true);
    try {
      await createAgenda({
        agenda: draft,
        ai_suggestion: source?.suggestion ?? null,
        model: source?.model ?? null,
        prompt_version: source?.promptVersion ?? null,
      });
      setMessage("Agenda saved.");
      setText("");
      setDraft(null);
      setSource(null);
      setEdited(new Set());
    } catch (caught) {
      setError(
        caught instanceof Error ? caught.message : "Could not save the agenda.",
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Paste an agenda</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-5">
        <form className="flex flex-col gap-3" onSubmit={handleParse}>
          <div className="flex flex-col gap-2">
            <Label htmlFor="agenda-source">Agenda text</Label>
            <textarea
              id="agenda-source"
              value={text}
              rows={5}
              maxLength={10000}
              onChange={(event) => setText(event.target.value)}
              placeholder="Paste an email, message, or meeting notes…"
              className="w-full rounded-md border border-line bg-white px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-spruce"
            />
            <span className="text-xs text-mist">
              {text.length.toLocaleString()} / 10,000 characters
            </span>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button type="submit" disabled={pending || !text.trim()}>
              {pending ? "Parsing…" : "Parse"}
            </Button>
            {pending ? (
              <Button
                type="button"
                variant="outline"
                onClick={() => controller.current?.abort()}
              >
                Cancel
              </Button>
            ) : null}
            <Button type="button" variant="outline" onClick={enterManually}>
              Enter manually
            </Button>
          </div>
        </form>

        {pending ? (
          <p role="status" className="text-sm text-mist">
            Parsing your text. This usually takes a few seconds…
          </p>
        ) : null}
        {message ? (
          <p role="status" className="text-sm text-spruce">
            {message}
          </p>
        ) : null}
        {error ? (
          <p role="alert" className="text-sm text-rust">
            {error}
          </p>
        ) : null}

        {draft ? (
          <form
            className="flex flex-col gap-5 border-t border-line pt-5"
            onSubmit={handleSave}
          >
            <div>
              <h3 className="font-medium">Review the agenda</h3>
              <p className="mt-1 text-xs text-mist">
                Suggestions are marked until you change them. Confirm the
                details before saving.
              </p>
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="flex flex-col gap-2">
                <Label htmlFor="agenda-title">
                  Title {suggested("title", draft.title)}
                </Label>
                <Input
                  id="agenda-title"
                  value={draft.title ?? ""}
                  onChange={(event) =>
                    updateField("title", event.target.value || null)
                  }
                />
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="agenda-starts-at">
                  Starts at (ISO 8601) {suggested("starts_at", draft.starts_at)}
                </Label>
                <Input
                  id="agenda-starts-at"
                  value={draft.starts_at ?? ""}
                  placeholder="2026-11-05T10:00:00+02:00"
                  onChange={(event) =>
                    updateField("starts_at", event.target.value || null)
                  }
                />
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="agenda-duration">
                  Duration in minutes{" "}
                  {suggested("duration_minutes", draft.duration_minutes)}
                </Label>
                <Input
                  id="agenda-duration"
                  type="number"
                  min={1}
                  max={600}
                  value={draft.duration_minutes ?? ""}
                  onChange={(event) =>
                    updateField(
                      "duration_minutes",
                      event.target.value ? Number(event.target.value) : null,
                    )
                  }
                />
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="agenda-language">
                  Language {suggested("language", draft.language)}
                </Label>
                <Input
                  id="agenda-language"
                  required
                  value={draft.language}
                  onChange={(event) =>
                    updateField("language", event.target.value)
                  }
                />
              </div>
            </div>

            <section className="flex flex-col gap-3">
              <div className="flex items-center justify-between gap-2">
                <h4 className="font-medium">Agenda items</h4>
                <Button
                  type="button"
                  variant="outline"
                  onClick={() =>
                    updateField("items", [
                      ...draft.items,
                      { topic: "", owner: null, minutes: null },
                    ])
                  }
                >
                  Add item
                </Button>
              </div>
              {draft.items.map((item, index) => (
                <div
                  key={index}
                  className="grid gap-3 rounded-md border border-line p-3 sm:grid-cols-3"
                >
                  <div className="flex flex-col gap-2">
                    <Label htmlFor={`agenda-topic-${index}`}>
                      Topic {suggested(`items.${index}.topic`, item.topic)}
                    </Label>
                    <Input
                      id={`agenda-topic-${index}`}
                      required
                      value={item.topic}
                      onChange={(event) =>
                        updateItem(index, "topic", event.target.value)
                      }
                    />
                  </div>
                  <div className="flex flex-col gap-2">
                    <Label htmlFor={`agenda-owner-${index}`}>
                      Owner {suggested(`items.${index}.owner`, item.owner)}
                    </Label>
                    <Input
                      id={`agenda-owner-${index}`}
                      value={item.owner ?? ""}
                      onChange={(event) =>
                        updateItem(index, "owner", event.target.value)
                      }
                    />
                  </div>
                  <div className="flex flex-col gap-2">
                    <Label htmlFor={`agenda-minutes-${index}`}>
                      Minutes{" "}
                      {suggested(`items.${index}.minutes`, item.minutes)}
                    </Label>
                    <Input
                      id={`agenda-minutes-${index}`}
                      type="number"
                      min={1}
                      max={480}
                      value={item.minutes ?? ""}
                      onChange={(event) =>
                        updateItem(index, "minutes", event.target.value)
                      }
                    />
                  </div>
                </div>
              ))}
            </section>

            <section className="flex flex-col gap-3">
              <div className="flex items-center justify-between gap-2">
                <h4 className="font-medium">Action items</h4>
                <Button
                  type="button"
                  variant="outline"
                  onClick={() =>
                    updateField("action_items", [
                      ...draft.action_items,
                      { task: "", owner: null, due: null },
                    ])
                  }
                >
                  Add action
                </Button>
              </div>
              {draft.action_items.map((item, index) => (
                <div
                  key={index}
                  className="grid gap-3 rounded-md border border-line p-3 sm:grid-cols-3"
                >
                  <div className="flex flex-col gap-2">
                    <Label htmlFor={`action-task-${index}`}>
                      Task {suggested(`action_items.${index}.task`, item.task)}
                    </Label>
                    <Input
                      id={`action-task-${index}`}
                      required
                      value={item.task}
                      onChange={(event) =>
                        updateAction(index, "task", event.target.value)
                      }
                    />
                  </div>
                  <div className="flex flex-col gap-2">
                    <Label htmlFor={`action-owner-${index}`}>
                      Owner{" "}
                      {suggested(`action_items.${index}.owner`, item.owner)}
                    </Label>
                    <Input
                      id={`action-owner-${index}`}
                      value={item.owner ?? ""}
                      onChange={(event) =>
                        updateAction(index, "owner", event.target.value)
                      }
                    />
                  </div>
                  <div className="flex flex-col gap-2">
                    <Label htmlFor={`action-due-${index}`}>
                      Due date{" "}
                      {suggested(`action_items.${index}.due`, item.due)}
                    </Label>
                    <Input
                      id={`action-due-${index}`}
                      type="date"
                      value={item.due ?? ""}
                      onChange={(event) =>
                        updateAction(index, "due", event.target.value)
                      }
                    />
                  </div>
                </div>
              ))}
            </section>

            {source?.model ? (
              <p className="text-xs text-mist">
                Parsed with {source.model} · prompt {source.promptVersion}
              </p>
            ) : (
              <p className="text-xs text-mist">
                This agenda is manual and has no AI suggestion attached.
              </p>
            )}
            <Button type="submit" disabled={saving}>
              {saving ? "Saving…" : "Save agenda"}
            </Button>
          </form>
        ) : null}
      </CardContent>
    </Card>
  );
}
