/** Server-assigned order number formatting and retry invariants. */
export function formatBusinessOrderNumber({businessDate,sequence,branchCode}){
 if(typeof businessDate!=="string"||!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(businessDate)||new Date(businessDate+"T00:00:00Z").toISOString().slice(0,10)!==businessDate)throw new Error("ORDER_NUMBER_BUSINESS_DATE_INVALID");
 if(!Number.isSafeInteger(sequence)||sequence<1||sequence>999999)throw new Error("ORDER_NUMBER_SEQUENCE_INVALID");
 if(typeof branchCode!=="string"||!/^[A-Z0-9]{2,10}$/.test(branchCode))throw new Error("ORDER_NUMBER_BRANCH_CODE_INVALID");
 return "DLC-"+businessDate.replaceAll("-","")+"-"+branchCode+"-"+String(sequence).padStart(6,"0");
}
export function assertOrderNumberRetry({existingNumber,idempotencyKey,requestedIdempotencyKey}){
 if(typeof requestedIdempotencyKey!=="string"||requestedIdempotencyKey.trim().length<16)throw new Error("ORDER_NUMBER_IDEMPOTENCY_REQUIRED");
 if(existingNumber&&idempotencyKey!==requestedIdempotencyKey)throw new Error("ORDER_NUMBER_IDEMPOTENCY_CONFLICT");
 return Object.freeze({order_number:existingNumber||null,idempotency_key:requestedIdempotencyKey,generate_only_if_absent:!existingNumber});
}
