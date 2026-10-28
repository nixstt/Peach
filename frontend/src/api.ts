export type Meeting = {
  id: number;
  title: string;
  starts_at: string;
  ends_at: string;
  attendee_count: number;
};

export type MeetingInput = {
  title: string;
  starts_at: string;
  ends_at: string;
  attendee_count: number;
};

const base = (import.meta.env.VITE_API_URL ?? "http://localhost:8000").replace(
  /\/$/,
  "",
);

export class ApiError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function formatDetail(detail: unknown): string {
  if (typeof detail === "string") {
    return detail;
  }
  if (Array.isArray(detail)) {
    return detail
      .map((item) => {
        if (typeof item === "object" && item && "msg" in item) {
          return String(item.msg);
        }
        return String(item);
      })
      .join(" ");
  }
  return "Request failed";
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${base}${path}`, {
    ...init,
    headers: {
      Accept: "application/json",
      ...(init?.body ? { "Content-Type": "application/json" } : {}),
      ...init?.headers,
    },
  });
  if (!response.ok) {
    let message = response.statusText || "Request failed";
    try {
      const body = (await response.json()) as { detail?: unknown };
      if (body.detail !== undefined) {
        message = formatDetail(body.detail);
      }
    } catch {
      // The body was not JSON. Keep the status text.
    }
    throw new ApiError(response.status, message);
  }
  return (await response.json()) as T;
}

export function listMeetings(): Promise<Meeting[]> {
  return request<Meeting[]>("/api/meetings");
}

export function createMeeting(input: MeetingInput): Promise<Meeting> {
  return request<Meeting>("/api/meetings", {
    method: "POST",
    body: JSON.stringify(input),
  });
}
