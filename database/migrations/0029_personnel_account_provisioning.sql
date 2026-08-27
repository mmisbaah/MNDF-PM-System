BEGIN;

ALTER TABLE accounts ADD COLUMN must_change_password boolean NOT NULL DEFAULT false;

COMMIT;
