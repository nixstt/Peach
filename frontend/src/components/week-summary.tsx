import { Card, CardContent } from "@/components/ui/card";
import type { Meeting } from "@/api";
import { countByWeek } from "@/lib/dates";

type WeekSummaryProps = {
  meetings: Meeting[];
};

export function WeekSummary({ meetings }: WeekSummaryProps) {
  const { thisWeek, lastWeek } = countByWeek(meetings, new Date());
  const delta = thisWeek - lastWeek;
  const deltaLabel =
    delta === 0
      ? "No change"
      : delta > 0
        ? `Up ${delta}`
        : `Down ${Math.abs(delta)}`;

  return (
    <section className="grid gap-3 sm:grid-cols-3" aria-label="Week over week">
      <Card>
        <CardContent className="py-4">
          <p className="text-xs uppercase tracking-wide text-mist">This week</p>
          <p className="mt-2 font-serif text-4xl tabular-nums">{thisWeek}</p>
        </CardContent>
      </Card>
      <Card>
        <CardContent className="py-4">
          <p className="text-xs uppercase tracking-wide text-mist">Last week</p>
          <p className="mt-2 font-serif text-4xl tabular-nums">{lastWeek}</p>
        </CardContent>
      </Card>
      <Card>
        <CardContent className="py-4">
          <p className="text-xs uppercase tracking-wide text-mist">
            Week over week
          </p>
          <p
            className={`mt-2 font-serif text-4xl ${delta < 0 ? "text-rust" : "text-spruce"}`}
          >
            {deltaLabel}
          </p>
        </CardContent>
      </Card>
    </section>
  );
}
