import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { Meeting } from "@/api";
import { formatRange } from "@/lib/dates";

type MeetingTableProps = {
  meetings: Meeting[];
  loading: boolean;
};

export function MeetingTable({ meetings, loading }: MeetingTableProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>All meetings</CardTitle>
      </CardHeader>
      <CardContent className="px-0 pb-2">
        <Table>
          <caption className="sr-only">Meetings</caption>
          <TableHeader>
            <TableRow>
              <TableHead>Title</TableHead>
              <TableHead>When</TableHead>
              <TableHead className="text-right">Attendees</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={3} className="text-mist">
                  Loading meetings…
                </TableCell>
              </TableRow>
            ) : null}
            {!loading && meetings.length === 0 ? (
              <TableRow>
                <TableCell colSpan={3} className="text-mist">
                  No meetings yet. Add the first one.
                </TableCell>
              </TableRow>
            ) : null}
            {!loading
              ? meetings.map((meeting) => (
                  <TableRow key={meeting.id}>
                    <TableCell className="font-medium">
                      {meeting.title}
                    </TableCell>
                    <TableCell>
                      {formatRange(meeting.starts_at, meeting.ends_at)}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {meeting.attendee_count}
                    </TableCell>
                  </TableRow>
                ))
              : null}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
