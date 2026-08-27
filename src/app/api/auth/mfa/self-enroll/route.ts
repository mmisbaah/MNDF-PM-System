import { NextRequest, NextResponse } from "next/server";
import { authenticateRequest } from "@/lib/auth/session";
import { encryptSecret } from "@/lib/auth/secrets";
import { loadMfaSecret, storePendingMfaSecret, withTenantTransaction } from "@/lib/auth/repository";
import { generateTotpSecret, totpUri } from "@/lib/auth/totp";

export const runtime = "nodejs";
export async function POST(request: NextRequest) {
  try {
    const principal = await authenticateRequest(request);
    if ((await loadMfaSecret(principal.tenantId, principal.accountId))?.active) return NextResponse.json({ success:false,error:"MFA is already enrolled" },{status:409});
    const identity=await withTenantTransaction(principal.tenantId,principal.accountId,async client=>(await client.query<{email:string;organization_name:string}>(`SELECT ac.email::text email,t.name organization_name FROM accounts ac JOIN tenants t ON t.id=ac.tenant_id WHERE ac.tenant_id=$1 AND ac.id=$2`,[principal.tenantId,principal.accountId])).rows[0]);
    if(!identity)return NextResponse.json({success:false,error:"Account not found"},{status:404});
    const secret=generateTotpSecret();
    await storePendingMfaSecret(principal.tenantId,principal.accountId,encryptSecret(secret));
    return NextResponse.json({success:true,secret,otpauthUri:totpUri(secret,identity.organization_name,identity.email)});
  } catch(error:any) { return NextResponse.json({success:false,error:error?.message??"MFA enrollment failed"},{status:error?.status??500}); }
}
