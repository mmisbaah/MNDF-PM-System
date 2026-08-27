BEGIN;

ALTER TABLE personnel
  DROP CONSTRAINT IF EXISTS personnel_personnel_category_check;

ALTER TABLE personnel
  ADD CONSTRAINT personnel_category_text_check
  CHECK (char_length(btrim(personnel_category)) BETWEEN 1 AND 80);

COMMIT;
