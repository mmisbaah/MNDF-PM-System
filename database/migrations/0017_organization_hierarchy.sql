\set ON_ERROR_STOP on

BEGIN;

ALTER TABLE organizational_nodes DROP CONSTRAINT organizational_nodes_node_type_check;
ALTER TABLE organizational_nodes ADD CONSTRAINT organizational_nodes_node_type_check
  CHECK (node_type IN (
    'ORGANIZATION','UNIT','DEPARTMENT','COMPANY','HEADQUARTERS','SECTION',
    'SUBSECTION','PLATOON','SQUAD','TEAM','OTHER'
  ));

ALTER TABLE organizational_nodes
  ADD COLUMN description text NOT NULL DEFAULT '',
  ADD COLUMN sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT clock_timestamp();

CREATE OR REPLACE FUNCTION guard_organizational_node_hierarchy()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.parent_id = NEW.id THEN
    RAISE EXCEPTION 'an organizational node cannot be its own parent';
  END IF;
  IF NEW.parent_id IS NOT NULL AND EXISTS (
    WITH RECURSIVE descendants AS (
      SELECT id FROM organizational_nodes WHERE tenant_id=NEW.tenant_id AND parent_id=NEW.id
      UNION ALL
      SELECT child.id FROM organizational_nodes child
      JOIN descendants d ON child.tenant_id=NEW.tenant_id AND child.parent_id=d.id
    ) SELECT 1 FROM descendants WHERE id=NEW.parent_id
  ) THEN
    RAISE EXCEPTION 'organizational hierarchy cycle is not allowed';
  END IF;
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END $$;

CREATE TRIGGER organizational_node_hierarchy_guard
  BEFORE INSERT OR UPDATE ON organizational_nodes
  FOR EACH ROW EXECUTE FUNCTION guard_organizational_node_hierarchy();
CREATE TRIGGER audit_organizational_nodes
  AFTER INSERT OR UPDATE OR DELETE ON organizational_nodes
  FOR EACH ROW EXECUTE FUNCTION audit_sensitive_change();

CREATE INDEX idx_org_nodes_display
  ON organizational_nodes (tenant_id,parent_id,sort_order,name);

COMMIT;
