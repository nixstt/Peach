export type Meeting = {
  id: number;
  title: string;
  starts_at: string;
  ends_at: string;
  attendee_count: number;
};

export type MeetingCreate = {
  title: string;
  starts_at: string;
  ends_at: string;
  attendee_count: number;
};

const API_URL = import.meta.env.VITE_API_URL;

export async function getMeetings(): Promise<Meeting[]> {
  const response = await fetch(`${API_URL}/api/meetings`);
  if (!response.ok) {
    throw new Error("Failed to load meetings");
  }
  return response.json();
}

export async function createMeeting(payload: MeetingCreate): Promise<Meeting> {
  const response = await fetch(`${API_URL}/api/meetings`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    const error = new Error("Failed to create meeting") as Error & { detail?: unknown };
    error.detail = body?.detail;
    throw error;
  }
  return response.json();
}
