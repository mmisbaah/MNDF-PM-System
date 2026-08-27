\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION recalculate_recommendations(p_tenant uuid,p_personnel uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_app record;
  v_score numeric;
  v_bad boolean;
  v_open boolean;
  v_eligible boolean;
  v_type recommendation_type;
BEGIN
  SELECT a.id,a.score_percentage,p.unit_service_started_on INTO v_app
    FROM appraisals a
    JOIN evaluation_cycles cy ON cy.tenant_id=a.tenant_id AND cy.id=a.cycle_id
      AND cy.cycle_type='ANNUAL' AND cy.data_mode='PRODUCTION'
    JOIN personnel p ON p.tenant_id=a.tenant_id AND p.id=a.personnel_id
   WHERE a.tenant_id=p_tenant AND a.personnel_id=p_personnel
     AND a.status IN ('APPROVED','ACKNOWLEDGED','CLOSED')
   ORDER BY cy.ends_on DESC LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT COALESCE(cv.score_percentage,v_app.score_percentage) INTO v_score
    FROM (SELECT 1) x
    LEFT JOIN LATERAL (
      SELECT score_percentage FROM appraisal_correction_versions
       WHERE tenant_id=p_tenant AND appraisal_id=v_app.id AND status='APPROVED'
       ORDER BY version_no DESC LIMIT 1
    ) cv ON true;

  IF EXISTS(
    SELECT 1 FROM appraisal_correction_versions
     WHERE tenant_id=p_tenant AND appraisal_id=v_app.id AND status='APPROVED'
  ) THEN
    SELECT EXISTS(
      SELECT 1
        FROM appraisal_correction_ratings cr
        JOIN appraisal_correction_versions cv
          ON cv.tenant_id=cr.tenant_id AND cv.id=cr.correction_version_id
       WHERE cv.tenant_id=p_tenant AND cv.appraisal_id=v_app.id AND cv.status='APPROVED'
         AND cv.version_no=(SELECT max(version_no) FROM appraisal_correction_versions
          WHERE tenant_id=p_tenant AND appraisal_id=v_app.id AND status='APPROVED')
         AND cr.rating<3
    ) INTO v_bad;
  ELSE
    SELECT EXISTS(
      SELECT 1 FROM appraisal_ratings
       WHERE tenant_id=p_tenant AND appraisal_id=v_app.id AND is_final AND rating<3
    ) INTO v_bad;
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM disciplinary_matters
     WHERE tenant_id=p_tenant AND personnel_id=p_personnel AND data_mode='PRODUCTION'
       AND status IN ('ALLEGED','UNDER_REVIEW','CONFIRMED')
  ) OR EXISTS(
    SELECT 1 FROM awol_incidents
     WHERE tenant_id=p_tenant AND personnel_id=p_personnel AND data_mode='PRODUCTION'
       AND status IN ('REPORTED','UNDER_REVIEW','CONFIRMED')
  ) INTO v_open;

  v_eligible:=v_score>85.00 AND NOT v_bad AND NOT v_open
    AND clock_timestamp() > (v_app.unit_service_started_on::timestamp + interval '9 months');
  PERFORM set_config('app.eligibility_engine','true',true);

  FOREACH v_type IN ARRAY ARRAY['PROMOTION'::recommendation_type,'COMMENDATION'::recommendation_type] LOOP
    INSERT INTO recommendations(
      tenant_id,personnel_id,annual_appraisal_id,recommendation_type,status,
      eligibility_checked_at,annual_score_percentage,has_rating_below_three,
      has_unresolved_disciplinary_matter,unit_service_started_on,eligible
    ) VALUES(
      p_tenant,p_personnel,v_app.id,v_type,
      (CASE WHEN v_eligible THEN 'ELIGIBLE' ELSE 'INELIGIBLE' END)::recommendation_status,
      clock_timestamp(),v_score,v_bad,v_open,v_app.unit_service_started_on,v_eligible
    )
    ON CONFLICT(tenant_id,personnel_id,annual_appraisal_id,recommendation_type)
    DO UPDATE SET
      eligibility_checked_at=EXCLUDED.eligibility_checked_at,
      annual_score_percentage=EXCLUDED.annual_score_percentage,
      has_rating_below_three=EXCLUDED.has_rating_below_three,
      has_unresolved_disciplinary_matter=EXCLUDED.has_unresolved_disciplinary_matter,
      unit_service_started_on=EXCLUDED.unit_service_started_on,
      eligible=EXCLUDED.eligible,
      status=CASE WHEN recommendations.status IN ('ELIGIBLE','INELIGIBLE')
        THEN EXCLUDED.status WHEN NOT EXCLUDED.eligible THEN 'INELIGIBLE' ELSE recommendations.status END;

    INSERT INTO recommendation_eligibility_assessments(
      tenant_id,recommendation_id,annual_score_percentage,has_rating_below_three,
      has_unresolved_disciplinary_matter,unit_service_started_on,service_threshold_at,eligible
    )
    SELECT p_tenant,id,v_score,v_bad,v_open,v_app.unit_service_started_on,
      v_app.unit_service_started_on::timestamp+interval '9 months',v_eligible
      FROM recommendations
     WHERE tenant_id=p_tenant AND personnel_id=p_personnel
       AND annual_appraisal_id=v_app.id AND recommendation_type=v_type;
  END LOOP;
END $$;

COMMIT;
