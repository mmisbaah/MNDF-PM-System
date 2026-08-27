import { formatDeadline } from "@/lib/grievance/deadline-engine";

type Props = { status: string; submissionDeadlineAt: string; acceptanceDeadlineAt?: string | null;
  decisionDeadlineAt?: string | null; isOverdue: boolean; overdueStage?: string | null };
export function ComplaintDeadlinePanel(props: Props) {
  const deadlines = [
    ["Submission", props.submissionDeadlineAt], ["Acceptance", props.acceptanceDeadlineAt], ["Final decision", props.decisionDeadlineAt],
  ].filter((entry): entry is [string, string] => Boolean(entry[1]));
  return <section aria-labelledby="complaint-deadlines" className="rounded-xl border border-slate-200 bg-white p-5">
    <div className="flex items-center justify-between gap-3">
      <h2 id="complaint-deadlines" className="font-semibold text-slate-900">Complaint deadlines</h2>
      <span className={props.isOverdue ? "rounded-full bg-red-100 px-3 py-1 text-sm font-semibold text-red-800" : "rounded-full bg-emerald-100 px-3 py-1 text-sm text-emerald-800"}>
        {props.isOverdue ? `Open · overdue (${props.overdueStage?.toLowerCase()})` : props.status.replaceAll("_", " ")}
      </span>
    </div>
    <dl className="mt-4 grid gap-3">{deadlines.map(([label, value]) => <div key={label}>
      <dt className="text-sm text-slate-500">{label} deadline</dt>
      <dd className="font-medium text-slate-900"><time dateTime={value}>{formatDeadline(value)}</time></dd>
    </div>)}</dl>
    <p className="mt-4 text-xs text-slate-500">All periods use server timestamps and include weekends and public holidays.</p>
  </section>;
}
