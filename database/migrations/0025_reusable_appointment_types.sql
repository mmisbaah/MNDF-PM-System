BEGIN;

CREATE TABLE appointment_types (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 120),
  role_description text NOT NULL CHECK (char_length(btrim(role_description)) BETWEEN 1 AND 1000),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,id)
);

CREATE UNIQUE INDEX appointment_types_active_name_uidx
  ON appointment_types (tenant_id,lower(name)) WHERE active;

ALTER TABLE appointments ADD COLUMN appointment_type_id uuid;

ALTER TABLE appointments DISABLE TRIGGER audit_appointments;

INSERT INTO appointment_types(tenant_id,name,role_description)
SELECT tenant_id,title,
       COALESCE(NULLIF(max(NULLIF(btrim(role_description),'')),''),'Standard responsibilities have not yet been entered.')
FROM appointments
GROUP BY tenant_id,title;

UPDATE appointments ap
SET appointment_type_id=type.id
FROM appointment_types type
WHERE type.tenant_id=ap.tenant_id AND lower(type.name)=lower(ap.title);

ALTER TABLE appointments ENABLE TRIGGER audit_appointments;

ALTER TABLE appointments ALTER COLUMN appointment_type_id SET NOT NULL;
ALTER TABLE appointments ADD CONSTRAINT appointments_type_fk
  FOREIGN KEY (tenant_id,appointment_type_id)
  REFERENCES appointment_types(tenant_id,id) ON DELETE RESTRICT;

CREATE TRIGGER audit_appointment_types
AFTER INSERT OR UPDATE OR DELETE ON appointment_types
FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();

COMMIT;
