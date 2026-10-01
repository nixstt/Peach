import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { Meeting } from "@/lib/api";

type MeetingTableProps = {
  meetings: Meeting[];
};

export function MeetingTable({ meetings }: MeetingTableProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>All meetings</CardTitle>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Title</TableHead>
              <TableHead>Starts at</TableHead>
              <TableHead>Ends at</TableHead>
              <TableHead>Attendees</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {meetings.length === 0 ? (
              <TableRow>
                <TableCell colSpan={4} className="text-muted-foreground">
                  No meetings yet.
                </TableCell>
              </TableRow>
            ) : (
              meetings.map((meeting) => (
                <TableRow key={meeting.id}>
                  <TableCell>{meeting.title}</TableCell>
                  <TableCell>{meeting.starts_at}</TableCell>
                  <TableCell>{meeting.ends_at}</TableCell>
                  <TableCell>{meeting.attendee_count}</TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
