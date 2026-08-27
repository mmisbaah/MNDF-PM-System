import test from"node:test";import assert from"node:assert/strict";
import{computeAppraisalScore}from"../src/lib/evaluation/score";import{resolveEvaluatorChain}from"../src/lib/evaluation/chain-engine";import{inspectEvidenceBuffer,validateRatingEvidence}from"../src/lib/evaluation/evidence";
import{MFA_REQUIRED_ROLES,ROLE_PERMISSIONS}from"../src/lib/auth/rbac";
import{BASELINE_TEMPLATE,BASELINE_CRITERIA_COUNT}from"../src/lib/evaluation/baseline-template";
test("score excludes criteria that do not apply",()=>{const result=computeAppraisalScore([{id:"a",applicableCategories:["PRIVATE"],applicableAppointmentTypes:null},{id:"b",applicableCategories:["OFFICER"],applicableAppointmentTypes:null}],[{criterionId:"a",rating:4}],"PRIVATE","RIFLEMAN");assert.deepEqual(result,{awardedPoints:4,maximumApplicablePoints:5,applicableCriteriaCount:1,percentage:80})});
test("extreme ratings require server upload id",()=>{assert.throws(()=>validateRatingEvidence(5,"documented exceptional performance"),/evidence attachment/);assert.doesNotThrow(()=>validateRatingEvidence(5,"documented exceptional performance",{uploadId:"11111111-1111-1111-1111-111111111111"}))});
test("evidence inspection rejects disguised content",()=>{assert.throws(()=>inspectEvidenceBuffer(Buffer.from("not a pdf"),"claim.pdf","application/pdf","tenant/key"),/does not match/)});
test("commander is excluded from evaluation",()=>{assert.throws(()=>resolveEvaluatorChain({appraiseePersonnelId:"p",appraiseeAppointmentType:"COMPANY_COMMANDER",appraiseeNodeId:"n",nodes:[],candidates:[]}),/excluded/)});
test("explicit chain rejects self evaluation",()=>{assert.throws(()=>resolveEvaluatorChain({appraiseePersonnelId:"p",appraiseeAppointmentType:"RIFLEMAN",appraiseeNodeId:"n",nodes:[],candidates:[],explicitAssignments:[{evaluatorPersonnelId:"p",evaluatorAccountId:"a",sequenceNo:1,kind:"FINAL_APPROVAL"}]}),/cannot evaluate/)});
test("commander approves but cannot submit ordinary ratings",()=>{assert.equal(ROLE_PERMISSIONS.COMPANY_COMMANDER.includes("appraisal.approve"),true);assert.equal(ROLE_PERMISSIONS.COMPANY_COMMANDER.includes("appraisal.evaluate"),false)});
test("dedicated administrator remains non-supervisory",()=>{
  const permissions=ROLE_PERMISSIONS.UNIT_ADMINISTRATOR;
  assert.equal(permissions.includes("personnel.manage"),true);
  assert.equal(permissions.includes("accounts.provision"),true);
  assert.equal(permissions.includes("report.read"),true);
  assert.equal(permissions.includes("organization.manage"),false);
  assert.equal(permissions.includes("appraisal.initialize"),false);
  assert.equal(permissions.includes("appraisal.evaluate"),false);
  assert.equal(permissions.includes("appraisal.approve"),false);
  assert.equal(permissions.includes("conduct.manage"),false);
});
test("conduct management is limited to supervisory leadership",()=>{
  assert.equal(ROLE_PERMISSIONS.FIRST_SERGEANT.includes("conduct.manage"),true);
  assert.equal(ROLE_PERMISSIONS.EXECUTIVE_OFFICER.includes("conduct.manage"),true);
  assert.equal(ROLE_PERMISSIONS.COMPANY_COMMANDER.includes("conduct.manage"),true);
  assert.equal(ROLE_PERMISSIONS.APPRAISEE.includes("conduct.manage"),false);
});
test("technical operator cannot access ordinary personnel or performance data",()=>{
  const permissions=ROLE_PERMISSIONS.TECHNICAL_OPERATOR;
  assert.equal(permissions.includes("operations.backup"),true);
  assert.equal(permissions.includes("operations.incident_response"),true);
  assert.equal(permissions.includes("personnel.read"),false);
  assert.equal(permissions.includes("report.read"),false);
  assert.equal(permissions.includes("appraisal.evaluate"),false);
  assert.equal(permissions.includes("appraisal.approve"),false);
});
test("privileged pilot roles require MFA",()=>{
  for(const role of ["COMPANY_COMMANDER","EXECUTIVE_OFFICER","FIRST_SERGEANT","UNIT_ADMINISTRATOR","TECHNICAL_OPERATOR"]as const){
    assert.equal(MFA_REQUIRED_ROLES.has(role),true,`${role} must require MFA`);
  }
});
test("pilot baseline contains all ten categories and at least thirty criteria",()=>{
  assert.equal(BASELINE_TEMPLATE.sections.length,10);
  assert.equal(BASELINE_CRITERIA_COUNT>=30,true);
  assert.deepEqual(BASELINE_TEMPLATE.sections.map(section=>section.name),[
    "Basic discipline","Followership","Leadership","Mental endurance","Physical endurance",
    "Example to others","Respect for time","Attendance","Decision-making","Islamic discipline",
  ]);
});
