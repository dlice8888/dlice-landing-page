import test from "node:test";
import assert from "node:assert/strict";
import { createSupabaseQualityComplianceAdapter } from "../../src/supabase-quality-compliance-adapter.mjs";

const base={tenantId:"tenant-a",branchId:"branch-a",actorId:"owner-a",idempotencyKey:"quality-idem-001"};
test("each Quality workflow delegates to exactly one atomic RPC",async()=>{
 const calls=[];const adapter=createSupabaseQualityComplianceAdapter({rpc:async(name,args)=>{calls.push({name,args});return {data:{status:"ok"},error:null}}});
 await adapter.requestFoodSafetyPolicy({...base,productClass:"chilled",minTempC:0,maxTempC:5,requiredAllergens:[],effectiveFrom:"2026-11-26T00:00:00Z"});
 await adapter.approveFoodSafetyPolicy({...base,policyId:"policy-a"});
 await adapter.requestSupplierQualityPolicy({...base,supplierId:"supplier-a",criticalFindingCodes:["SEAL"],effectiveFrom:"2026-11-26T00:00:00Z"});
 await adapter.approveSupplierQualityPolicy({...base,policyId:"supplier-policy-a"});
 await adapter.registerFoodLot({...base,sourceType:"receipt_item",sourceId:"receipt-item-a",lotCode:"LOT-A",quantity:10,unit:"kg"});
 await adapter.linkFoodLotDistribution({...base,lotId:"lot-a",impactType:"order",impactEntityId:"order-a"});
 await adapter.recordFoodSafetyInspection({...base,sourceType:"receipt_item",sourceId:"receipt-item-a",lotCode:"LOT-A",policyId:"policy-a",measuredTempC:4,declaredAllergens:[]});
 await adapter.initiateFoodRecall({...base,lotCode:"LOT-A",reason:"contamination alert",severity:"high"});
 await adapter.recordSupplierQualityInspection({...base,receiptItemId:"receipt-item-a",policyId:"supplier-policy-a",findings:[{code:"PACKAGING",severity:"major"}]});
 await adapter.submitSupplierCorrectiveAction({...base,capaId:"capa-a",rootCause:"Root cause",correctiveAction:"Correction",preventiveAction:"Prevention",evidenceReference:"evidence://capa"});
 await adapter.verifySupplierCorrectiveAction({...base,capaId:"capa-a",decision:"verified",evidenceReference:"evidence://verify",releaseQuarantine:true});
 assert.equal(calls.length,11);
 assert.deepEqual(calls.map(x=>x.name),[
  "quality_request_food_safety_policy","quality_approve_food_safety_policy",
  "quality_request_supplier_quality_policy","quality_approve_supplier_quality_policy",
  "quality_register_food_lot","quality_link_food_lot_distribution",
  "quality_record_food_safety_inspection","quality_initiate_food_recall",
  "quality_record_supplier_quality_inspection","quality_submit_supplier_capa","quality_verify_supplier_capa"
 ]);
 assert.equal(calls[10].args.p_release_quarantine,true);
});
test("adapter fails closed without an RPC client or required tenant scope",async()=>{
 assert.throws(()=>createSupabaseQualityComplianceAdapter({}),{code:"QUALITY_RPC_CLIENT_REQUIRED"});
 const adapter=createSupabaseQualityComplianceAdapter({rpc:async()=>({data:null,error:null})});
 await assert.rejects(adapter.initiateFoodRecall({branchId:"branch-a",actorId:"owner-a",lotCode:"LOT",reason:"reason",severity:"high",idempotencyKey:"quality-idem-001"}),{code:"QUALITY_INPUT_REQUIRED"});
});
test("database errors preserve their SQLSTATE",async()=>{
 const adapter=createSupabaseQualityComplianceAdapter({rpc:async()=>({data:null,error:{code:"23514",message:"FOOD_RECALL_TRACEABILITY_INCOMPLETE"}})});
 await assert.rejects(adapter.initiateFoodRecall({...base,lotCode:"LOT-A",reason:"contamination",severity:"critical"}),{code:"23514"});
});
