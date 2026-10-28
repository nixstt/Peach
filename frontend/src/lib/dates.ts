export function toUtcZ(localValue: string): string {
  const date = new Date(localValue);
  if (Number.isNaN(date.getTime())) {
    throw new Error("invalid date");
  }
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

export function startOfLocalWeek(date: Date): Date {
  const copy = new Date(date.getTime());
  const mondayIndex = (copy.getDay() + 6) % 7;
  copy.setHours(0, 0, 0, 0);
  copy.setDate(copy.getDate() - mondayIndex);
  return copy;
}

export function countByWeek(
  meetings: { starts_at: string }[],
  now: Date,
): { thisWeek: number; lastWeek: number } {
  const thisStart = startOfLocalWeek(now);
  const nextStart = new Date(thisStart);
  nextStart.setDate(nextStart.getDate() + 7);
  const lastStart = new Date(thisStart);
  lastStart.setDate(lastStart.getDate() - 7);

  let thisWeek = 0;
  let lastWeek = 0;
  for (const meeting of meetings) {
    const when = new Date(meeting.starts_at);
    if (when >= thisStart && when < nextStart) {
      thisWeek += 1;
    } else if (when >= lastStart && when < thisStart) {
      lastWeek += 1;
    }
  }
  return { thisWeek, lastWeek };
}

export function formatRange(startsAt: string, endsAt: string): string {
  const start = new Date(startsAt);
  const end = new Date(endsAt);
  const day = new Intl.DateTimeFormat(undefined, {
    weekday: "short",
    month: "short",
    day: "numeric",
  });
  const time = new Intl.DateTimeFormat(undefined, {
    hour: "numeric",
    minute: "2-digit",
  });
  if (start.toDateString() === end.toDateString()) {
    return `${day.format(start)} · ${time.format(start)} – ${time.format(end)}`;
  }
  return `${day.format(start)}, ${time.format(start)} – ${day.format(end)}, ${time.format(end)}`;
}
