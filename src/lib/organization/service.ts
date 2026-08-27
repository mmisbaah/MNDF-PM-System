import { withTenantTransaction } from "@/lib/auth/repository";
import { EvaluationDomainError } from "@/lib/evaluation/errors";

const NODE_TYPES = new Set([
  "ORGANIZATION", "UNIT", "DEPARTMENT", "COMPANY", "HEADQUARTERS", "SECTION",
  "SUBSECTION", "PLATOON", "SQUAD", "TEAM", "OTHER",
]);

type NodeInput = { parentId?: string | null; levelDefinitionId?: string; nodeType?: string; code?: string; name?: string; description?: string; sortOrder?: number; active?: boolean };
type LevelInput = { levelNumber?: number; name?: string; code?: string };

export async function createOrganizationLevelDefinition(tenantId:string,accountId:string,input:LevelInput){
  const levelNumber=Number(input.levelNumber);
  if(!Number.isInteger(levelNumber)||levelNumber<1||levelNumber>10)throw new EvaluationDomainError("Level number must be between 1 and 10",422,"ORG_LEVEL_NUMBER_INVALID");
  if(!input.name?.trim()||input.name.trim().length>80)throw new EvaluationDomainError("Level name must contain 1-80 characters",422,"ORG_LEVEL_NAME_INVALID");
  if(!input.code?.trim()||!/^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$/.test(input.code.trim()))throw new EvaluationDomainError("Level code must be 1-32 letters, numbers, dots, underscores, or hyphens",422,"ORG_LEVEL_CODE_INVALID");
  return withTenantTransaction(tenantId,accountId,async client=>{
    if(levelNumber>1){const previous=(await client.query("SELECT 1 FROM organization_level_definitions WHERE tenant_id=$1 AND level_number=$2 AND active",[tenantId,levelNumber-1])).rows[0];if(!previous)throw new EvaluationDomainError("Create the preceding organizational level first",422,"ORG_PREVIOUS_LEVEL_REQUIRED")}
    try{return(await client.query(`INSERT INTO organization_level_definitions(tenant_id,level_number,name,code)VALUES($1,$2,$3,$4)RETURNING *`,[tenantId,levelNumber,input.name!.trim(),input.code!.trim()])).rows[0]}
    catch(error:any){if(error?.code==="23505")throw new EvaluationDomainError("That organizational level already exists",409,"ORG_LEVEL_EXISTS");throw error}
  });
}

function validate(input: NodeInput, creating: boolean) {
  if (creating && !input.levelDefinitionId) {
    throw new EvaluationDomainError("A configured organizational level is required",422,"ORG_LEVEL_REQUIRED");
  }
  if (creating || input.code !== undefined) {
    if (!input.code?.trim() || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$/.test(input.code.trim())) throw new EvaluationDomainError("Code must be 1-32 letters, numbers, dots, underscores, or hyphens",422,"ORG_NODE_CODE_INVALID");
  }
  if (creating || input.name !== undefined) {
    if (!input.name?.trim() || input.name.trim().length > 120) throw new EvaluationDomainError("Organizational node name is required and must not exceed 120 characters",422,"ORG_NODE_NAME_INVALID");
  }
  if (input.sortOrder !== undefined && (!Number.isInteger(input.sortOrder) || input.sortOrder < 0)) throw new EvaluationDomainError("Sort order must be a non-negative integer",422,"ORG_NODE_SORT_INVALID");
}

export async function createOrganizationNode(tenantId:string,accountId:string,input:NodeInput){
  validate(input,true);
  return withTenantTransaction(tenantId,accountId,async c=>{
    const level=(await c.query<{level_number:number}>("SELECT level_number FROM organization_level_definitions WHERE tenant_id=$1 AND id=$2 AND active",[tenantId,input.levelDefinitionId])).rows[0];
    if(!level)throw new EvaluationDomainError("Configured organizational level not found",422,"ORG_LEVEL_NOT_FOUND");
    if(input.parentId){const parent=(await c.query<{level_number:number|null}>(`SELECT d.level_number FROM organizational_nodes n LEFT JOIN organization_level_definitions d ON d.tenant_id=n.tenant_id AND d.id=n.level_definition_id WHERE n.tenant_id=$1 AND n.id=$2 AND n.active`,[tenantId,input.parentId])).rows[0];if(!parent)throw new EvaluationDomainError("Active parent node not found",422,"ORG_PARENT_NOT_FOUND");const parentLevel=parent.level_number??0;if(level.level_number!==parentLevel+1)throw new EvaluationDomainError("The selected structure type must be immediately below its parent",422,"ORG_LEVEL_PARENT_MISMATCH");}else if(level.level_number!==1)throw new EvaluationDomainError("Only a Level 1 structure may have no parent",422,"ORG_TOP_LEVEL_REQUIRED");
    try{return (await c.query(`INSERT INTO organizational_nodes(tenant_id,parent_id,level_definition_id,node_type,code,name,description,sort_order) VALUES($1,$2,$3,'OTHER',$4,$5,$6,$7) RETURNING *`,[tenantId,input.parentId??null,input.levelDefinitionId,input.code!.trim(),input.name!.trim(),input.description?.trim()??"",level.level_number])).rows[0];}
    catch(error:any){if(error?.code==="23505")throw new EvaluationDomainError("Organizational code already exists in this unit",409,"ORG_CODE_EXISTS");throw error;}
  });
}

export async function updateOrganizationNode(tenantId:string,accountId:string,id:string,input:NodeInput){
  validate(input,false);
  return withTenantTransaction(tenantId,accountId,async c=>{
    const current=(await c.query<{active:boolean;parent_id:string|null;level_definition_id:string|null}>("SELECT active,parent_id,level_definition_id FROM organizational_nodes WHERE tenant_id=$1 AND id=$2 FOR UPDATE",[tenantId,id])).rows[0];
    if(!current)throw new EvaluationDomainError("Organizational node not found",404,"ORG_NODE_NOT_FOUND");
    if(input.active===false){const used=await c.query(`SELECT EXISTS(SELECT 1 FROM organizational_nodes WHERE tenant_id=$1 AND parent_id=$2 AND active) OR EXISTS(SELECT 1 FROM appointments WHERE tenant_id=$1 AND organizational_node_id=$2 AND active) AS used`,[tenantId,id]);if(used.rows[0].used)throw new EvaluationDomainError("Move or deactivate active child nodes and appointments first",409,"ORG_NODE_IN_USE");}
    const parentId=input.parentId!==undefined?input.parentId:current.parent_id;const levelId=input.levelDefinitionId??current.level_definition_id;
    if(levelId){const level=(await c.query<{level_number:number}>("SELECT level_number FROM organization_level_definitions WHERE tenant_id=$1 AND id=$2 AND active",[tenantId,levelId])).rows[0];if(!level)throw new EvaluationDomainError("Configured organizational level not found",422,"ORG_LEVEL_NOT_FOUND");if(parentId){const parent=(await c.query<{level_number:number|null}>(`SELECT d.level_number FROM organizational_nodes n LEFT JOIN organization_level_definitions d ON d.tenant_id=n.tenant_id AND d.id=n.level_definition_id WHERE n.tenant_id=$1 AND n.id=$2 AND n.active`,[tenantId,parentId])).rows[0];if(!parent)throw new EvaluationDomainError("Active parent node not found",422,"ORG_PARENT_NOT_FOUND");if(level.level_number!==(parent.level_number??0)+1)throw new EvaluationDomainError("The selected structure type must be immediately below its parent",422,"ORG_LEVEL_PARENT_MISMATCH");}else if(level.level_number!==1)throw new EvaluationDomainError("Only a Level 1 structure may have no parent",422,"ORG_TOP_LEVEL_REQUIRED");
      try{return (await c.query(`UPDATE organizational_nodes SET parent_id=$3,level_definition_id=$4,node_type='OTHER',code=COALESCE($5,code),name=COALESCE($6,name),description=COALESCE($7,description),sort_order=$8,active=COALESCE($9,active) WHERE tenant_id=$1 AND id=$2 RETURNING *`,[tenantId,id,parentId,levelId,input.code?.trim(),input.name?.trim(),input.description?.trim(),level.level_number,input.active])).rows[0];}catch(error:any){if(error?.code==="23505")throw new EvaluationDomainError("Organizational code already exists in this unit",409,"ORG_CODE_EXISTS");if(error?.message?.includes("cycle"))throw new EvaluationDomainError("Moving this element would create a hierarchy cycle",422,"ORG_HIERARCHY_CYCLE");throw error;}}
    return (await c.query(`UPDATE organizational_nodes SET code=COALESCE($3,code),name=COALESCE($4,name),description=COALESCE($5,description),active=COALESCE($6,active) WHERE tenant_id=$1 AND id=$2 RETURNING *`,[tenantId,id,input.code?.trim(),input.name?.trim(),input.description?.trim(),input.active])).rows[0];
  });
}
