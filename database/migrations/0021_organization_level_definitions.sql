\set ON_ERROR_STOP on
BEGIN;

CREATE TABLE IF NOT EXISTS organization_level_definitions(
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  level_number smallint NOT NULL CHECK(level_number BETWEEN 1 AND 10),
  name text NOT NULL CHECK(btrim(name)<>''),
  code citext NOT NULL CHECK(btrim(code::text)<>''),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(tenant_id,id),
  UNIQUE(tenant_id,level_number)
);
ALTER TABLE organization_level_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_level_definitions FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON organization_level_definitions USING(tenant_id=current_tenant_id()) WITH CHECK(tenant_id=current_tenant_id());

ALTER TABLE organizational_nodes ADD COLUMN level_definition_id uuid;
ALTER TABLE organizational_nodes ADD CONSTRAINT organizational_nodes_level_definition_fk
  FOREIGN KEY(tenant_id,level_definition_id) REFERENCES organization_level_definitions(tenant_id,id) ON DELETE RESTRICT;

SELECT set_config('app.tenant_id',(SELECT tenant_id::text FROM system_installation WHERE singleton),true);

INSERT INTO organization_level_definitions(tenant_id,level_number,name,code)
SELECT tenant_id,sort_order,
  CASE WHEN sort_order=1 THEN 'Section' ELSE 'Subsection' END,
  CASE WHEN sort_order=1 THEN 'SECTION' ELSE 'SUBSECTION-'||sort_order END
FROM organizational_nodes WHERE sort_order BETWEEN 1 AND 10
GROUP BY tenant_id,sort_order;

UPDATE organizational_nodes n SET level_definition_id=d.id
FROM organization_level_definitions d
WHERE d.tenant_id=n.tenant_id AND d.level_number=n.sort_order AND n.parent_id IS NOT NULL;

CREATE INDEX idx_organization_level_definitions_display ON organization_level_definitions(tenant_id,level_number) WHERE active;
GRANT SELECT,INSERT,UPDATE,DELETE ON organization_level_definitions TO mndf_pms_runtime;

COMMIT;
