BEGIN;

ALTER TABLE appointment_types
  ADD COLUMN system_administrator_operator boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN appointment_types.system_administrator_operator IS
  'True only for appointment types whose current holders may operate the dedicated System Administrator account after Authorizer approval.';

COMMIT;
