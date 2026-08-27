export class EvaluationDomainError extends Error {
  constructor(
    message: string,
    public readonly status: 400 | 403 | 404 | 409 | 422 = 400,
    public readonly code = "EVALUATION_ERROR",
  ) {
    super(message);
  }
}
