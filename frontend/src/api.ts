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

export type WeeklyReportRequest = {
  request_id: number;
  week: string;
  status: string;
};

export type AgendaItem = {
  topic: string;
  owner: string | null;
  minutes: number | null;
};

export type ActionItem = {
  task: string;
  owner: string | null;
  due: string | null;
};

export type ParsedAgenda = {
  title: string | null;
  starts_at: string | null;
  duration_minutes: number | null;
  items: AgendaItem[];
  action_items: ActionItem[];
  language: string;
};

export type ParsedAgendaResponse = {
  agenda: ParsedAgenda;
  model: string;
  prompt_version: string;
};

export type AgendaInput = {
  agenda: ParsedAgenda;
  ai_suggestion: ParsedAgenda | null;
  model: string | null;
  prompt_version: string | null;
};

export type SavedAgenda = AgendaInput & {
  id: number;
  created_at: string;
};

const base = (import.meta.env.VITE_API_URL ?? "http://localhost:8000").replace(
  /\/$/,
  "",
);
const parserUrl = (import.meta.env.VITE_AI_PARSER_URL ?? "").replace(/\/$/, "");

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

/** Call this from a React component when the auth state changes. */
let _accessToken: string | null = null;
export function setAccessToken(token: string | null): void {
  _accessToken = token;
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const authHeaders: Record<string, string> = _accessToken
    ? { Authorization: `Bearer ${_accessToken}` }
    : {};

  const response = await fetch(`${base}${path}`, {
    ...init,
    headers: {
      Accept: "application/json",
      ...(init?.body ? { "Content-Type": "application/json" } : {}),
      ...authHeaders,
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

export function requestWeeklyReport(): Promise<WeeklyReportRequest> {
  return request<WeeklyReportRequest>("/api/reports/weekly", {
    method: "POST",
  });
}

export class AgendaParseError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export async function parseAgenda(
  text: string,
  today: string,
  tz: string,
  signal: AbortSignal,
): Promise<ParsedAgendaResponse> {
  if (!parserUrl) {
    throw new AgendaParseError(0, "AI parsing is not configured for this app.");
  }
  const response = await fetch(parserUrl, {
    method: "POST",
    signal,
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      ...(_accessToken ? { Authorization: `Bearer ${_accessToken}` } : {}),
    },
    body: JSON.stringify({ text, today, tz }),
  });
  if (!response.ok) {
    let message = response.statusText || "The parser request failed.";
    try {
      const body = (await response.json()) as { error?: unknown };
      if (typeof body.error === "string") {
        message = body.error;
      }
    } catch {
      // Keep the HTTP status when the parser returns a non-JSON error.
    }
    throw new AgendaParseError(response.status, message);
  }
  return (await response.json()) as ParsedAgendaResponse;
}

export function createAgenda(input: AgendaInput): Promise<SavedAgenda> {
  return request<SavedAgenda>("/api/agendas", {
    method: "POST",
    body: JSON.stringify(input),
  });
}
