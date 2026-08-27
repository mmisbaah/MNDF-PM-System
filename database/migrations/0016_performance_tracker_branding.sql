\set ON_ERROR_STOP on

UPDATE evaluation_templates
SET name = 'Performance Tracker Pilot Baseline'
WHERE name = 'MNDF PMS Pilot Baseline';
