import { describe, expect, it } from "vitest";

import { countByWeek, startOfLocalWeek, toUtcZ } from "./dates";

describe("toUtcZ", () => {
  it("turns a datetime-local value into UTC with a Z and no milliseconds", () => {
    const local = new Date(2026, 9, 1, 12, 0, 0);
    const pad = (value: number) => String(value).padStart(2, "0");
    const input = `${local.getFullYear()}-${pad(local.getMonth() + 1)}-${pad(local.getDate())}T${pad(local.getHours())}:${pad(local.getMinutes())}`;
    expect(toUtcZ(input)).toBe(local.toISOString().replace(/\.\d{3}Z$/, "Z"));
  });

  it("rejects a value that is not a date", () => {
    expect(() => toUtcZ("not-a-date")).toThrow("invalid date");
  });
});

describe("countByWeek", () => {
  it("counts the current local week and the one before it", () => {
    const now = new Date(2026, 9, 28, 15, 0, 0);
    const thisStart = startOfLocalWeek(now);

    const thisMeeting = new Date(thisStart);
    thisMeeting.setDate(thisMeeting.getDate() + 1);
    thisMeeting.setHours(9, 0, 0, 0);

    const lastMeeting = new Date(thisStart);
    lastMeeting.setDate(lastMeeting.getDate() - 2);
    lastMeeting.setHours(9, 0, 0, 0);

    const older = new Date(thisStart);
    older.setDate(older.getDate() - 10);

    expect(
      countByWeek(
        [
          { starts_at: thisMeeting.toISOString() },
          { starts_at: lastMeeting.toISOString() },
          { starts_at: older.toISOString() },
        ],
        now,
      ),
    ).toEqual({ thisWeek: 1, lastWeek: 1 });
  });
});
