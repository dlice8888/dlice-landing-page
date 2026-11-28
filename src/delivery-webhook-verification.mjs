/**
 * Provider-neutral delivery webhook verification contract.
 * A provider adapter must supply its documented signature header and secret.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const hex=(bytes)=>[...new Uint8Array(bytes)].map(x=>x.toString(16).padStart(2,"0")).join("");
function equalConstantTime(a,b){if(a.length!==b.length)return false;let d=0;for(let i=0;i<a.length;i++)d|=a.charCodeAt(i)^b.charCodeAt(i);return d===0;}
export async function verifyDeliveryWebhook({rawBody,signature,timestamp,secret,nowMs=Date.now(),maxSkewSeconds=300}) {
 if(typeof rawBody!=="string"||!rawBody.length)fail("RAW_BODY_REQUIRED","Raw webhook body is required");
 if(typeof signature!=="string"||!signature.trim())fail("SIGNATURE_REQUIRED","Provider signature is required");
 if(typeof secret!=="string"||secret.length<16)fail("WEBHOOK_SECRET_INVALID","Configured provider secret is missing or too short");
 const ts=Number(timestamp);if(!Number.isSafeInteger(ts))fail("TIMESTAMP_INVALID","Signed timestamp is required");
 if(Math.abs(Math.floor(nowMs/1000)-ts)>maxSkewSeconds)fail("WEBHOOK_TIMESTAMP_OUT_OF_WINDOW","Webhook timestamp is outside replay window");
 const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
 const expected=hex(await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(`${ts}.${rawBody}`)));
 const supplied=signature.replace(/^sha256=/i,"").toLowerCase();
 if(!equalConstantTime(expected,supplied))fail("WEBHOOK_SIGNATURE_INVALID","Provider signature does not match raw request body");
 let payload;try{payload=JSON.parse(rawBody);}catch{fail("WEBHOOK_JSON_INVALID","Webhook body is not valid JSON");}
 if(!payload||typeof payload.event_id!=="string"||!payload.event_id.trim()||typeof payload.dispatch_id!=="string"||!payload.dispatch_id.trim())fail("WEBHOOK_IDENTITY_REQUIRED","Webhook requires stable event_id and dispatch_id");
 return Object.freeze({verified:true,eventId:payload.event_id,dispatchId:payload.dispatch_id,payload,bodySha256:hex(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(rawBody)))});
}
export function deliveryWebhookEventDecision({eventId,bodySha256,existingEvent}) {
 if(!eventId||!bodySha256)fail("WEBHOOK_IDENTITY_REQUIRED","Event id and body hash are required");
 if(!existingEvent)return Object.freeze({action:"insert_and_process"});
 if(existingEvent.bodySha256!==bodySha256)fail("WEBHOOK_EVENT_ID_COLLISION","Same provider event id arrived with a different payload");
 return Object.freeze({action:"ack_duplicate",existingEventId:existingEvent.id});
}
export function deliveryStorageUploadIntent({tenantId,branchId,dispatchId,fileName,mimeType,sizeBytes}) {
 for(const [k,v] of Object.entries({tenantId,branchId,dispatchId,fileName,mimeType}))if(typeof v!=="string"||!v.trim())fail("UPLOAD_METADATA_REQUIRED",k);
 if(!/^image\/(jpeg|png|webp)$/.test(mimeType))fail("UPLOAD_MIME_NOT_ALLOWED","Proof upload must be JPEG, PNG or WebP");
 if(!Number.isSafeInteger(sizeBytes)||sizeBytes<=0||sizeBytes>10*1024*1024)fail("UPLOAD_SIZE_INVALID","Proof upload must be 1 byte to 10 MiB");
 const safeName=fileName.normalize("NFKC").replace(/[^a-zA-Z0-9._-]/g,"_").slice(-100);
 if(!safeName)fail("UPLOAD_FILENAME_INVALID","Filename is empty after normalization");
 return Object.freeze({bucket:"delivery-proof",objectPath:`${tenantId}/${branchId}/${dispatchId}/${crypto.randomUUID()}-${safeName}`,upsert:false,private:true});
}
