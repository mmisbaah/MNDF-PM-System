\set ON_ERROR_STOP on

ALTER TABLE evaluation_cycles
  ADD COLUMN closure_due_on date
  GENERATED ALWAYS AS (ends_on + 25) STORED;

CREATE INDEX idx_cycles_lifecycle
  ON evaluation_cycles (tenant_id, cycle_type, starts_on, closure_due_on, status);

COMMENT ON COLUMN evaluation_cycles.closure_due_on IS
  'Calendar date 25 days after the period end; quarterly cycles close after this date.';
