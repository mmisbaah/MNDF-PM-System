import { EvaluationDomainError } from "./errors";

export type ScoreableCriterion = {
  id: string;
  applicableCategories: readonly string[];
  applicableAppointmentTypes: readonly string[] | null;
};

export type FinalRating = { criterionId: string; rating: number };

export type ScoreResult = {
  awardedPoints: number;
  maximumApplicablePoints: number;
  applicableCriteriaCount: number;
  percentage: number;
};

export function criterionApplies(
  criterion: ScoreableCriterion,
  personnelCategory: string,
  appointmentType: string,
): boolean {
  return criterion.applicableCategories.includes(personnelCategory)
    && (criterion.applicableAppointmentTypes === null
      || criterion.applicableAppointmentTypes.includes(appointmentType));
}

export function computeAppraisalScore(
  criteria: readonly ScoreableCriterion[],
  ratings: readonly FinalRating[],
  personnelCategory: string,
  appointmentType: string,
): ScoreResult {
  const applicable = criteria.filter((criterion) => criterionApplies(criterion, personnelCategory, appointmentType));
  if (applicable.length === 0) {
    throw new EvaluationDomainError("No applicable criteria exist for this personnel category and appointment", 422, "NO_APPLICABLE_CRITERIA");
  }

  const byCriterion = new Map<string, number>();
  for (const rating of ratings) {
    if (!Number.isInteger(rating.rating) || rating.rating < 1 || rating.rating > 5) {
      throw new EvaluationDomainError("Every rating must be an integer from 1 to 5", 422, "INVALID_RATING");
    }
    if (byCriterion.has(rating.criterionId)) {
      throw new EvaluationDomainError("Only one final rating is allowed per applicable criterion", 409, "DUPLICATE_FINAL_RATING");
    }
    byCriterion.set(rating.criterionId, rating.rating);
  }

  const missing = applicable.filter((criterion) => !byCriterion.has(criterion.id));
  if (missing.length > 0) {
    throw new EvaluationDomainError(`Missing ${missing.length} required final rating(s)`, 422, "INCOMPLETE_RATINGS");
  }

  const applicableIds = new Set(applicable.map((criterion) => criterion.id));
  const awardedPoints = ratings
    .filter((rating) => applicableIds.has(rating.criterionId))
    .reduce((sum, rating) => sum + rating.rating, 0);
  const maximumApplicablePoints = applicable.length * 5;

  return {
    awardedPoints,
    maximumApplicablePoints,
    applicableCriteriaCount: applicable.length,
    percentage: Math.round((awardedPoints / maximumApplicablePoints) * 10_000) / 100,
  };
}
