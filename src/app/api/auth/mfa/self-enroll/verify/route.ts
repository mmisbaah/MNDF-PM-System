import { NextRequest, NextResponse } from "next/server";
import { authenticateRequest } from "@/lib/auth/session";
import { activateMfa, loadMfaSecret, mfaVerificationBlocked, recordMfaVerification } from "@/lib/auth/repository";
import { decryptSecret } from "@/lib/auth/secrets";
import { verifyTotp } from "@/lib/auth/totp";

export const runtime="nodejs";
export async function POST(request:NextRequest){
  try{
    const principal=await authenticateRequest(request),body=await request.json().catch(()=>null)as{code?:string}|null;
    if(!body?.code)return NextResponse.json({success:false,error:"A six-digit code is required"},{status:422});
    if(await mfaVerificationBlocked(principal.tenantId,principal.accountId))return NextResponse.json({success:false,error:"Too many MFA attempts. Try again after ten minutes."},{status:429});
    const factor=await loadMfaSecret(principal.tenantId,principal.accountId);
    if(!factor||factor.active)return NextResponse.json({success:false,error:factor?.active?"MFA is already enrolled":"Start MFA enrollment first"},{status:409});
    const valid=verifyTotp(decryptSecret(factor.encryptedSecret),body.code);
    await recordMfaVerification(principal.tenantId,principal.accountId,valid);
    if(!valid)return NextResponse.json({success:false,error:"Invalid authentication code"},{status:401});
    await activateMfa(principal.tenantId,principal.accountId);
    return NextResponse.json({success:true});
  }catch(error:any){return NextResponse.json({success:false,error:error?.message??"MFA verification failed"},{status:error?.status??500})}
}
