/** Branch-local hours, cutoff and capacity policy. */
const zones=new Set(["Asia/Jakarta","Asia/Makassar","Asia/Jayapura"]);
const parts=(instant,zone)=>Object.fromEntries(new Intl.DateTimeFormat("en-GB",{timeZone:zone,weekday:"short",hour:"2-digit",minute:"2-digit",hourCycle:"h23"}).formatToParts(new Date(instant)).map(p=>[p.type,p.value]));
export function quoteBranchAvailability({now,timezone,operatingHours,holidayDates=[],cutoffMinutes=0,capacityUsed=0,capacityLimit,requestedAt=now}){
 if(!zones.has(timezone))throw new Error("ORDER_AVAILABILITY_TIMEZONE_INVALID");
 const instant=Date.parse(requestedAt),current=Date.parse(now);if(!Number.isFinite(instant)||!Number.isFinite(current)||instant<current)throw new Error("ORDER_AVAILABILITY_TIME_INVALID");
 if(!Number.isInteger(cutoffMinutes)||cutoffMinutes<0||!Number.isInteger(capacityUsed)||capacityUsed<0||!Number.isInteger(capacityLimit)||capacityLimit<1)throw new Error("ORDER_AVAILABILITY_CAPACITY_INVALID");
 const p=parts(instant,timezone),dateParts=Object.fromEntries(new Intl.DateTimeFormat("en-CA",{timeZone:timezone,year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date(instant)).map(x=>[x.type,x.value])),date=dateParts.year+"-"+dateParts.month+"-"+dateParts.day;
 if(holidayDates.includes(date))return Object.freeze({available:false,reason:"holiday",business_date:date,timezone});
 const hours=operatingHours?.[p.weekday];if(!hours?.open||!hours?.close)return Object.freeze({available:false,reason:"closed",business_date:date,timezone});
 const minutes=Number(p.hour)*60+Number(p.minute),open=Number(hours.open.slice(0,2))*60+Number(hours.open.slice(3,5)),close=Number(hours.close.slice(0,2))*60+Number(hours.close.slice(3,5));
 if(minutes<open||minutes>=close)return Object.freeze({available:false,reason:"outside_operating_hours",business_date:date,timezone});
 if(close-minutes<=cutoffMinutes)return Object.freeze({available:false,reason:"cutoff_passed",business_date:date,timezone});
 if(capacityUsed>=capacityLimit)return Object.freeze({available:false,reason:"capacity_full",business_date:date,timezone});
 return Object.freeze({available:true,reason:null,business_date:date,timezone,remaining_capacity:capacityLimit-capacityUsed});
}
