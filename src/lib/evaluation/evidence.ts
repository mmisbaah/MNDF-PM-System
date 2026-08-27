import { EvaluationDomainError } from "./errors";
import { createHash } from "node:crypto";

export const ACCEPTED_EVIDENCE_MIME_TYPES = [
  "application/pdf",
  "image/jpeg",
  "image/png",
  "image/webp",
] as const;

export type EvidenceInput = {
  uploadId: string;
};

export function validateRatingEvidence(rating: number, justification: string | null, evidence?: EvidenceInput): void {
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    throw new EvaluationDomainError("Rating must be an integer from 1 to 5", 422, "INVALID_RATING");
  }
  const extreme = rating === 1 || rating === 2 || rating === 5;
  if (extreme && (!justification || justification.trim().length < 10)) {
    throw new EvaluationDomainError("Ratings 1, 2, and 5 require a meaningful text justification", 422, "JUSTIFICATION_REQUIRED");
  }
  if (extreme && !evidence) {
    throw new EvaluationDomainError("Ratings 1, 2, and 5 require one evidence attachment", 422, "EVIDENCE_REQUIRED");
  }
  if (!evidence) return;
  if (!/^[0-9a-f-]{36}$/i.test(evidence.uploadId))
    throw new EvaluationDomainError("Evidence requires a server-issued upload identifier",422,"INVALID_EVIDENCE_UPLOAD");
}

export function inspectEvidenceBuffer(
  bytes: Buffer,
  originalFilename: string,
  declaredMimeType: string,
  storageKey: string,
): Omit<EvidenceInput,"uploadId"> & {storageKey:string;originalFilename:string;mimeType:string;byteSize:number;pageCount:number;sha256Hex:string} {
  if (bytes.length === 0 || bytes.length > 5 * 1024 * 1024) {
    throw new EvaluationDomainError("Evidence must contain data and must not exceed 5 MB", 422, "EVIDENCE_TOO_LARGE");
  }
  const detectedMimeType = detectMimeType(bytes);
  if (!detectedMimeType || detectedMimeType !== declaredMimeType) {
    throw new EvaluationDomainError("Evidence content does not match its declared PDF or image type", 422, "EVIDENCE_SIGNATURE_MISMATCH");
  }
  const pageCount = detectedMimeType === "application/pdf" ? conservativePdfPageCount(bytes) : 1;
  if (pageCount !== 1) {
    throw new EvaluationDomainError("PDF evidence must contain exactly one page", 422, "EVIDENCE_PAGE_LIMIT");
  }
  return {
    storageKey,
    originalFilename,
    mimeType: detectedMimeType,
    byteSize: bytes.length,
    pageCount,
    sha256Hex: createHash("sha256").update(bytes).digest("hex"),
  };
}

function detectMimeType(bytes: Buffer): (typeof ACCEPTED_EVIDENCE_MIME_TYPES)[number] | null {
  if (bytes.subarray(0, 5).toString("ascii") === "%PDF-") return "application/pdf";
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return "image/png";
  if (bytes.subarray(0, 4).toString("ascii") === "RIFF" && bytes.subarray(8, 12).toString("ascii") === "WEBP") return "image/webp";
  return null;
}

function conservativePdfPageCount(bytes: Buffer): number {
  // Pilot uploads are capped at 5 MiB and one page. PDFs whose page tree cannot be
  // established conservatively are rejected instead of trusting client metadata.
  const source = bytes.toString("latin1");
  return source.match(/\/Type\s*\/Page(?!s)\b/g)?.length ?? 0;
}
