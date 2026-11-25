/**
 * Supabase adapter for Quality & Compliance.
 * Each method performs exactly one PostgreSQL RPC; the DB function owns the transaction.
 * Never compose these methods into a multi-request pseudo-transaction.
 */
const required=(value,field)=>{
 if(typeof value!=="string"||!value.trim()){const error=new Error(field+" is required");error.code="QUALITY_INPUT_REQUIRED";throw error;}
 return value.trim();
};
export function createSupabaseQualityComplianceAdapter(client){
 if(typeof client?.rpc!=="function"){const error=new Error("A Supabase service-role RPC client is required");error.code="QUALITY_RPC_CLIENT_REQUIRED";throw error;}
 const invoke=async(functionName,args)=>{
  const {data,error}=await client.rpc(functionName,args);
  if(error){const failure=new Error(error.message||"Quality database operation failed");failure.code=error.code||"QUALITY_RPC_FAILED";throw failure;}
  return data;
 };
 return Object.freeze({
  requestFoodSafetyPolicy(input){return invoke("quality_request_food_safety_policy",{
   p_tenant_id:required(input.tenantId,"tenantId"),p_branch_id:required(input.branchId,"branchId"),
   p_product_class:required(input.productClass,"productClass"),p_min_temp_c:input.minTempC,p_max_temp_c:input.maxTempC,
   p_required_allergens:input.requiredAllergens,p_effective_from:required(input.effectiveFrom,"effectiveFrom"),
   p_effective_until:input.effectiveUntil??null,p_idempotency_key:required(input.idempotencyKey,"idempotencyKey"),
   p_actor_user_id:required(input.actorId,"actorId")});},
  approveFoodSafetyPolicy(input){return invoke("quality_approve_food_safety_policy",{
   p_tenant_id:required(input.tenantId,"tenantId"),p_branch_id:required(input.branchId,"branchId"),
   p_policy_id:required(input.policyId,"policyId"),p_actor_user_id:required(input.actorId,"actorId")});},
  requestSupplierQualityPolicy(input){return invoke("quality_request_supplier_quality_policy",{
   p_tenant_id:required(input.tenantId,"tenantId"),p_branch_id:required(input.branchId,"branchId"),
   p_supplier_id:required(input.supplierId,"supplierId"),p_critical_finding_codes:input.criticalFindingCodes,
   p_effective_from:required(input.effectiveFrom,"effectiveFrom"),p_effective_until:input.effectiveUntil??null,
   p_idempotency_key:required(input.idempotencyKey,"idempotencyKey"),p_actor_user_id:required(input.actorId,"actorId")});},
  approveSupplierQualityPolicy(input){return invoke("quality_approve_supplier_quality_policy",{
   p_tenant_id:required(input.tenantId,"tenantId"),p_branch_id:required(input.branchId,"branchId"),
   p_policy_id:required(input.policyId,"policyId"),p_actor_user_id:required(input.actorId,"actorId")});},
  registerFoodLot(input){return invoke("quality_register_food_lot",{
   p_tenant_id:required(input.tenantId,"tenantId"),p_branch_id:required(input.branchId,"branchId"),
   p_source_type:required(input.sourceType,"sourceType"),p_source_id:required(input.sourceId,"sourceId"),
   p_lot_code:required(input.lotCode,"lotCode"),p_quantity:input.quantity,p_unit:required(input.unit,"unit"),
   p_idempotency_key:required(input.idempotencyKey,"idempotencyKey"),p_actor_user_id:required(input.actorId,"actorId")});},
  linkFoodLotDistribution(input){return invoke("quality_link_food_lot_distribution",{
   p_tenant_id:required(input.tenantId,"tenantId"),p_branch_id:required(input.branchId,"branchId"),
   p_lot_id:required(input.lotId,"lotId"),p_impact_type:required(input.impactType,"impactType"),
   p_impact_entity_id:required(input.impactEntityId,"impactEntityId"),p_quantity:input.quantity??null,
   p_idempotency_key:required(input.idempotencyKey,"idempotencyKey"),p_actor_user_id:required(input.actorId,"actorId")});},
  recordFoodSafetyInspection(input){return invoke("quality_record_food_safety_inspection",{
   p_tenant_id:required(input.tenantId,"tenantId"),p_branch_id:required(input.branchId,"branchId"),
   p_source_type:required(input.sourceType,"sourceType"),p_source_id:required(input.sourceId,"sourceId"),
   p_lot_code:required(input.lotCode,"lotCode"),p_policy_id:required(input.policyId,"policyId"),
   p_measured_temp_c:input.measuredTempC,p_declared_allergens:input.declaredAllergens,
   p_idempotency_key:required(input.idempotencyKey,"idempotencyKey"),p_actor_user_id:required(input.actorId,"actorId")});},
  initiateFoodRecall(input){return invoke("quality_initiate_food_recall",{
   p_tenant_id:required(input.tenantId,"tenantId"),p_branch_id:required(input.branchId,"branchId"),
   p_lot_code:required(input.lotCode,"lotCode"),p_reason:required(input.reason,"reason"),
   p_severity:required(input.severity,"severity"),p_idempotency_key:required(input.idempotencyKey,"idempotencyKey"),
   p_actor_user_id:required(input.actorId,"actorId")});},
  recordSupplierQualityInspection(input){return invoke("quality_record_supplier_quality_inspection",{
   p_tenant_id:required(input.tenantId,"tenantId"),p_branch_id:required(input.branchId,"branchId"),
   p_receipt_item_id:required(input.receiptItemId,"receiptItemId"),p_policy_id:required(input.policyId,"policyId"),
   p_findings:input.findings,p_idempotency_key:required(input.idempotencyKey,"idempotencyKey"),
   p_actor_user_id:required(input.actorId,"actorId")});},
  requestFoodLotRelease(input){return invoke("quality_request_food_lot_release",{
   p_tenant_id:required(input.tenantId,"tenantId"),p_branch_id:required(input.branchId,"branchId"),
   p_quarantine_id:required(input.quarantineId,"quarantineId"),p_reason:required(input.reason,"reason"),
   p_evidence_reference:required(input.evidenceReference,"evidenceReference"),
   p_idempotency_key:required(input.idempotencyKey,"idempotencyKey"),p_actor_user_id:required(input.actorId,"actorId")});},
  approveFoodLotRelease(input){return invoke("quality_approve_food_lot_release",{
   p_tenant_id:required(input.tenantId,"tenantId"),p_branch_id:required(input.branchId,"branchId"),
   p_quarantine_id:required(input.quarantineId,"quarantineId"),p_decision:required(input.decision,"decision"),
   p_evidence_reference:required(input.evidenceReference,"evidenceReference"),
   p_idempotency_key:required(input.idempotencyKey,"idempotencyKey"),p_actor_user_id:required(input.actorId,"actorId")});},
  submitSupplierCorrectiveAction(input){return invoke("quality_submit_supplier_capa",{
   p_tenant_id:required(input.tenantId,"tenantId"),p_branch_id:required(input.branchId,"branchId"),
   p_capa_id:required(input.capaId,"capaId"),p_root_cause:required(input.rootCause,"rootCause"),
   p_corrective_action:required(input.correctiveAction,"correctiveAction"),
   p_preventive_action:required(input.preventiveAction,"preventiveAction"),
   p_evidence_reference:required(input.evidenceReference,"evidenceReference"),
   p_actor_user_id:required(input.actorId,"actorId")});},
  verifySupplierCorrectiveAction(input){return invoke("quality_verify_supplier_capa",{
   p_tenant_id:required(input.tenantId,"tenantId"),p_branch_id:required(input.branchId,"branchId"),
   p_capa_id:required(input.capaId,"capaId"),p_decision:required(input.decision,"decision"),
   p_evidence_reference:required(input.evidenceReference,"evidenceReference"),
   p_release_quarantine:input.releaseQuarantine===true,p_actor_user_id:required(input.actorId,"actorId")});},
 });
}
