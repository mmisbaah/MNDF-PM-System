BEGIN;

ALTER TABLE appointments
  ADD COLUMN role_description text NOT NULL DEFAULT '';

CREATE UNIQUE INDEX appointments_active_title_node_uidx
  ON appointments (tenant_id, organizational_node_id, lower(title))
  WHERE active;

COMMIT;
