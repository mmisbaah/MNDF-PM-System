BEGIN;

ALTER TABLE appointment_types
  ADD COLUMN leadership_priority smallint
  CHECK (leadership_priority BETWEEN 1 AND 100);

ALTER TABLE personnel
  ADD COLUMN rank_precedence smallint CHECK (rank_precedence BETWEEN 1 AND 1000),
  ADD COLUMN date_of_rank date,
  ADD COLUMN manual_precedence smallint CHECK (manual_precedence BETWEEN 1 AND 1000);

COMMIT;
