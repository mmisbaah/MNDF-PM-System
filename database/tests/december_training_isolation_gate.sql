\set ON_ERROR_STOP on

DO $$
DECLARE v_count bigint;
BEGIN
  SELECT count(*) INTO v_count FROM evaluation_cycles
   WHERE daterange(starts_on,ends_on,'[]') && daterange(DATE '2026-12-01',DATE '2026-12-31','[]')
     AND data_mode <> 'TRAINING';
  IF v_count > 0 THEN RAISE EXCEPTION '% December evaluation cycle(s) are not training data',v_count; END IF;

  SELECT count(*) INTO v_count FROM activity_records
   WHERE activity_date BETWEEN DATE '2026-12-01' AND DATE '2026-12-31' AND data_mode <> 'TRAINING';
  IF v_count > 0 THEN RAISE EXCEPTION '% December activity record(s) are not training data',v_count; END IF;

  SELECT count(*) INTO v_count FROM operational_reports
   WHERE daterange(period_start,period_end,'[]') && daterange(DATE '2026-12-01',DATE '2026-12-31','[]')
     AND data_mode <> 'TRAINING';
  IF v_count > 0 THEN RAISE EXCEPTION '% December operational report(s) are not training data',v_count; END IF;

  SELECT count(*) INTO v_count FROM disciplinary_matters
   WHERE occurred_on BETWEEN DATE '2026-12-01' AND DATE '2026-12-31' AND data_mode <> 'TRAINING';
  IF v_count > 0 THEN RAISE EXCEPTION '% December disciplinary matter(s) are not training data',v_count; END IF;

  SELECT count(*) INTO v_count FROM awol_incidents
   WHERE started_at >= TIMESTAMPTZ '2026-12-01 00:00:00+05'
     AND started_at < TIMESTAMPTZ '2027-01-01 00:00:00+05' AND data_mode <> 'TRAINING';
  IF v_count > 0 THEN RAISE EXCEPTION '% December AWOL incident(s) are not training data',v_count; END IF;

  SELECT count(*) INTO v_count FROM report_exports export
   JOIN appraisals appraisal ON appraisal.tenant_id=export.tenant_id AND appraisal.id=export.appraisal_id
   JOIN evaluation_cycles cycle ON cycle.tenant_id=appraisal.tenant_id AND cycle.id=appraisal.cycle_id
   WHERE cycle.data_mode='TRAINING' AND export.data_mode='PRODUCTION';
  IF v_count > 0 THEN RAISE EXCEPTION '% production report export(s) reference training appraisals',v_count; END IF;

  SELECT count(*) INTO v_count FROM recommendations recommendation
   JOIN appraisals appraisal ON appraisal.tenant_id=recommendation.tenant_id AND appraisal.id=recommendation.annual_appraisal_id
   JOIN evaluation_cycles cycle ON cycle.tenant_id=appraisal.tenant_id AND cycle.id=appraisal.cycle_id
   WHERE cycle.data_mode='TRAINING';
  IF v_count > 0 THEN RAISE EXCEPTION '% eligibility recommendation(s) reference training appraisals',v_count; END IF;
END $$;

SELECT 'december_training_isolation_gate_passed' AS result;

