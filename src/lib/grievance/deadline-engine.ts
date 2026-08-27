export const MALDIVES_TIME_ZONE = "Indian/Maldives";

export function addCalendarDays(timestamp: Date | string, days: number): Date {
  const value = new Date(timestamp);
  if (Number.isNaN(value.getTime())) throw new TypeError("Invalid server timestamp");
  return new Date(value.getTime() + days * 24 * 60 * 60 * 1000);
}

export function complaintDeadlines(availableAt: Date | string, submittedAt?: Date | string, acceptedAt?: Date | string) {
  return {
    submissionDeadlineAt: addCalendarDays(availableAt, 3),
    acceptanceDeadlineAt: submittedAt ? addCalendarDays(submittedAt, 3) : null,
    decisionDeadlineAt: acceptedAt ? addCalendarDays(acceptedAt, 5) : null,
  };
}

export function formatDeadline(timestamp: Date | string): string {
  return new Intl.DateTimeFormat("en-MV", {
    dateStyle: "full", timeStyle: "long", timeZone: MALDIVES_TIME_ZONE,
  }).format(new Date(timestamp));
}
